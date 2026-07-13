"""Stage D of the Government Promises Tracker evidence-trail expansion:
periodic re-verification of a promise's implementation_quality against its
accumulated promise_evidence, run by a separate weekly job (not the news
cron) since Parliament Q&A / CAG reports update far slower than news.

Answers the two questions the one-shot per-article extraction can't: was
this promise acted on, and if so, was it done properly - verified
independently, not just claimed by the government.
"""

from __future__ import annotations

import logging

from ai_processor.groq_processor import process_govt_promise_reverification
from database.supabase_client import (
    fetch_promise_evidence,
    fetch_promises_needing_reverification,
    update_promise_verification,
)

logger = logging.getLogger(__name__)

# Same three source_type values the Flutter side treats as independent (see
# lib/src/models/govt_promise.dart::PromiseEvidenceSourceTypeLabel.isIndependent)
# and the Stage D prompt's own rule
# (groq_processor._GOVT_PROMISE_REVERIFICATION_SYSTEM_PROMPT). Kept as a
# constant here because this check must not rely on Groq having followed
# that rule correctly - it is re-applied independently of the model's own
# stated reasoning.
INDEPENDENT_SOURCE_TYPES = {"parliament_qa", "cag_report", "prs_legislative"}


def _apply_business_rules(payload: dict, evidence_rows: list[dict]) -> dict:
    """Groq is probabilistic - the prompt rule alone isn't a guarantee (same
    lesson groq_processor._sanitize_enums already encodes for enum drift).
    This re-checks evidence_rows directly, which the model's own output
    never proves it actually did, and downgrades the verdict if it claims
    fully_implemented without at least one independent-source excerpt."""
    if payload.get("implementation_quality") == "fully_implemented":
        has_independent = any(row.get("source_type") in INDEPENDENT_SOURCE_TYPES for row in evidence_rows)
        if not has_independent:
            logger.warning(
                "Downgrading implementation_quality fully_implemented -> "
                "partially_implemented: no independent-source evidence for promise %s",
                payload.get("promise_id", "<unknown>"),
            )
            payload["implementation_quality"] = "partially_implemented"
    return payload


def reverify_promise(promise: dict) -> bool:
    """Runs Stage D for one promise. Returns True if the promise's
    verification fields were updated, False if there was no new evidence to
    re-verify against or the Groq call/validation failed."""
    evidence_rows = fetch_promise_evidence(promise["id"])
    if not evidence_rows:
        return False

    last_verified_at = promise.get("last_verified_at")
    if last_verified_at is not None:
        has_new_evidence = any(row["observed_at"] > last_verified_at for row in evidence_rows)
        if not has_new_evidence:
            return False

    result = process_govt_promise_reverification(promise, evidence_rows)
    if result is None:
        return False

    payload = result.model_dump(mode="json")
    payload["promise_id"] = promise["id"]
    payload = _apply_business_rules(payload, evidence_rows)

    update_promise_verification(promise["id"], payload)
    return True


def run_promise_reverification() -> None:
    """Entry point for the weekly reverification job (see
    .github/workflows/promise_verification_cron.yml,
    `python src/main.py --sources promise_verification`). Batches over every
    non-cancelled promise with evidence newer than its last verification."""
    candidates = fetch_promises_needing_reverification()
    updated = 0
    for promise in candidates:
        if reverify_promise(promise):
            updated += 1
    logger.info("Promise reverification: %d/%d promises updated", updated, len(candidates))
