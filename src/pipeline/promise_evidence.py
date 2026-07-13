"""Stage B of the Government Promises Tracker evidence-trail expansion:
matches an incoming article from an evidence-trail source (PRS Legislative,
sansad.in eLibrary — see main._PROMISE_EVIDENCE_SOURCES) against tracked
govt_promises by fuzzy title match, then records it as a promise_evidence
row with a Groq-classified stance.

Fuzzy title-matching (reusing utils.fuzzy_match, already proven for
crisis/public_event dedup) is a placeholder here, not a final answer -
project names ("Mumbai Metro Line 3") and PRS bill titles ("The Constitution
(131st Amendment) Bill, 2026") or eLibrary document titles often share very
little vocabulary. Once real matching accuracy is observed in production,
an embedding-based match (reusing ai_processor.embeddings.embed_text, the
same dependency pipeline.public_events already uses for public_events dedup)
may be needed instead.
"""

from __future__ import annotations

import logging

from ai_processor.groq_processor import process_promise_evidence_stance
from database.supabase_client import fetch_govt_promise_match_candidates, insert_promise_evidence
from models.schemas import RawContentItem
from utils.fuzzy_match import title_similarity, STRICT_TITLE_MATCH_THRESHOLD

logger = logging.getLogger(__name__)

# Maps fetcher RawContentItem.source values to promise_evidence.source_type.
# "sansad_elibrary" deliberately maps to "other", NOT "parliament_qa" - see
# fetchers/sansad_elibrary.py's module docstring for why (it's a general
# document-repository search, not confirmed to be scoped to actual written
# Q&A records, so it must not count toward the independent-evidence
# threshold pipeline.promise_reverification enforces for "parliament_qa").
_SOURCE_TYPE_MAP = {
    "prs_legislative": "prs_legislative",
    "sansad_elibrary": "other",
}


def _best_matching_promise(article_title: str, candidates: list[dict]) -> dict | None:
    # Candidates here are every tracked promise, not a pre-narrowed
    # same-event set - see STRICT_TITLE_MATCH_THRESHOLD's docstring for why
    # DEDUP_TITLE_THRESHOLD is unsafe for this call site.
    best: dict | None = None
    best_score = 0.0
    for candidate in candidates:
        score = title_similarity(article_title, candidate["project_name"])
        if score > best_score:
            best_score = score
            best = candidate
    if best is not None and best_score >= STRICT_TITLE_MATCH_THRESHOLD:
        return best
    return None


def process_promise_evidence_item(item: RawContentItem) -> None:
    """Entry point called from main.process_and_store() for items tagged
    with a source in _PROMISE_EVIDENCE_SOURCES. Skips Groq entirely if
    nothing matches (no point spending a call on an article about an
    untracked bill/scheme)."""
    candidates = fetch_govt_promise_match_candidates()
    if not candidates:
        return

    match = _best_matching_promise(item.title, candidates)
    if match is None:
        return

    classification = process_promise_evidence_stance(
        promise_name=match["project_name"],
        official_claim=match.get("official_claim"),
        headline=item.title,
        text=item.text,
    )
    if classification is None:
        return

    insert_promise_evidence(
        {
            "promise_id": match["id"],
            "source_type": _SOURCE_TYPE_MAP.get(item.source, "other"),
            "source_url": item.url,
            "stance": classification.stance.value,
            "excerpt_summary": classification.excerpt_summary,
        }
    )
    logger.info(
        "Recorded promise evidence for %s (stance=%s) from %s",
        match["project_name"],
        classification.stance.value,
        item.source,
    )
