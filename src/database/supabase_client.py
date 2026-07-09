"""Supabase client and deduplicating upsert logic for fact_checks / crisis_reports."""

from __future__ import annotations

import logging
import os
from typing import Optional

from supabase import Client, create_client

logger = logging.getLogger(__name__)

_client: Optional[Client] = None


def get_client() -> Client:
    """Lazily create and cache the Supabase client from env vars."""
    global _client
    if _client is None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_KEY"]
        _client = create_client(url, key)
    return _client


def fact_check_exists(claim_text: str, source_url: str) -> bool:
    """True if a fact check with this exact claim text or source URL already exists."""
    client = get_client()

    if source_url:
        by_url = (
            client.table("fact_checks").select("id").eq("source_url", source_url).limit(1).execute()
        )
        if by_url.data:
            return True

    by_claim = client.table("fact_checks").select("id").eq("claim_text", claim_text).limit(1).execute()
    return bool(by_claim.data)


def crisis_report_exists(title: str, source_url: str) -> bool:
    """True if a crisis report with this exact title or source URL already exists."""
    client = get_client()

    if source_url:
        by_url = (
            client.table("crisis_reports")
            .select("id")
            .eq("source_url", source_url)
            .limit(1)
            .execute()
        )
        if by_url.data:
            return True

    by_title = client.table("crisis_reports").select("id").eq("title", title).limit(1).execute()
    return bool(by_title.data)


def find_by_headline_hash(table: str, headline_hash: str) -> Optional[str]:
    """Fast exact-match dedup check, run before the embedding-based
    find_similar_* lookups (see supabase/migrations/0007_rate_limiting_and_headline_hash.sql).
    """
    result = get_client().table(table).select("id").eq("headline_hash", headline_hash).limit(1).execute()
    return result.data[0]["id"] if result.data else None


def find_similar_fact_check(embedding: list[float], threshold: float) -> Optional[str]:
    """Return the id of an existing fact check with cosine similarity > threshold, or None."""
    result = get_client().rpc(
        "match_fact_checks",
        {"query_embedding": embedding, "match_threshold": threshold, "match_count": 1},
    ).execute()
    return result.data[0]["id"] if result.data else None


def find_similar_crisis_report(embedding: list[float], threshold: float) -> Optional[str]:
    """Return the id of an existing crisis report with cosine similarity > threshold, or None."""
    result = get_client().rpc(
        "match_crisis_reports",
        {"query_embedding": embedding, "match_threshold": threshold, "match_count": 1},
    ).execute()
    return result.data[0]["id"] if result.data else None


def append_fact_check_source(row_id: str, source: dict) -> None:
    """Atomically append a new source to an existing fact check's `sources` array."""
    get_client().rpc("append_fact_check_source", {"row_id": row_id, "new_source": source}).execute()
    logger.info("Appended new evidence source to fact check %s", row_id)


def append_crisis_evidence(row_id: str, evidence: dict) -> None:
    """Atomically append a new evidence item to an existing crisis report's `evidence_items` array."""
    get_client().rpc("append_crisis_evidence", {"row_id": row_id, "new_evidence": evidence}).execute()
    logger.info("Appended new evidence item to crisis report %s", row_id)


EVIDENCE_BUCKET = "evidence_vault"


def upload_to_supabase_storage(image_bytes: bytes, filename: str, content_type: str) -> str:
    """Upload raw image bytes to the public evidence_vault bucket, return its public URL.

    Used to re-host Reddit-linked images so evidence survives even if the
    original post or image is later deleted.
    """
    bucket = get_client().storage.from_(EVIDENCE_BUCKET)
    bucket.upload(
        path=filename,
        file=image_bytes,
        file_options={"content-type": content_type, "upsert": "true"},
    )
    return bucket.get_public_url(filename)


def insert_fact_check(data: dict) -> Optional[str]:
    """Insert a fact check row, skipping if a duplicate already exists.

    Returns the new row's id if inserted, None if skipped as a duplicate.
    """
    if fact_check_exists(data["claim_text"], data.get("source_url", "")):
        logger.info("Skipping duplicate fact check: %s", data["claim_text"][:80])
        return None

    result = get_client().table("fact_checks").insert(data).execute()
    logger.info("Inserted fact check: %s", data["claim_text"][:80])
    return result.data[0]["id"]


def insert_crisis_report(data: dict) -> Optional[str]:
    """Insert a crisis report row, skipping if a duplicate already exists.

    Returns the new row's id if inserted, None if skipped as a duplicate.
    """
    if crisis_report_exists(data["title"], data.get("source_url", "")):
        logger.info("Skipping duplicate crisis report: %s", data["title"][:80])
        return None

    result = get_client().table("crisis_reports").insert(data).execute()
    logger.info("Inserted crisis report: %s", data["title"][:80])
    return result.data[0]["id"]


# ---------------------------------------------------------------------------
# Source tracking / coverage / fact_checks_v2 — see
# supabase/migrations/0006_source_tracking_and_fact_checks_v2.sql
# ---------------------------------------------------------------------------

_CONSENSUS_HIGH_MIN = 8
_CONSENSUS_MEDIUM_MIN = 3


def _consensus_for(total_outlets: int) -> str:
    if total_outlets >= _CONSENSUS_HIGH_MIN:
        return "high"
    if total_outlets >= _CONSENSUS_MEDIUM_MIN:
        return "medium"
    return "low"


def insert_outlet_source(
    *,
    fact_check_id: Optional[str] = None,
    crisis_report_id: Optional[str] = None,
    outlet_name: str,
    outlet_url: str,
    publish_time: Optional[str],
    outlet_credibility_score: Optional[float],
) -> None:
    """Record that `outlet_name` covered this fact_check/crisis_report row.

    Upserts on (fact_check_id, outlet_url) or (crisis_report_id, outlet_url)
    so re-processing the same outlet's item is a no-op, not a duplicate row.
    """
    on_conflict = "fact_check_id,outlet_url" if fact_check_id else "crisis_report_id,outlet_url"
    get_client().table("outlet_sources").upsert(
        {
            "fact_check_id": fact_check_id,
            "crisis_report_id": crisis_report_id,
            "outlet_name": outlet_name,
            "outlet_url": outlet_url,
            "publish_time": publish_time,
            "outlet_credibility_score": outlet_credibility_score,
        },
        on_conflict=on_conflict,
    ).execute()


def recompute_coverage(*, fact_check_id: Optional[str] = None, crisis_report_id: Optional[str] = None) -> int:
    """Recount outlet_sources for this row and upsert the coverage_analysis
    cache row. Call after insert_outlet_source. Returns the recomputed
    total_outlets count (used by pipeline.public_events.compute_importance_score
    as a real media-coverage signal)."""
    client = get_client()
    column = "fact_check_id" if fact_check_id else "crisis_report_id"
    row_id = fact_check_id or crisis_report_id

    rows = client.table("outlet_sources").select("outlet_name").eq(column, row_id).execute()
    outlets_list = sorted({row["outlet_name"] for row in rows.data})

    client.table("coverage_analysis").upsert(
        {
            "fact_check_id": fact_check_id,
            "crisis_report_id": crisis_report_id,
            "total_outlets": len(outlets_list),
            "outlets_list": outlets_list,
            "consensus": _consensus_for(len(outlets_list)),
        },
        on_conflict=column,
    ).execute()
    return len(outlets_list)


def insert_fact_check_v2(data: dict) -> None:
    """Insert/replace the legally-safe claim-level fact-check for a
    fact_checks row (1:1 via the fact_check_id unique constraint)."""
    get_client().table("fact_checks_v2").upsert(data, on_conflict="fact_check_id").execute()
    logger.info("Upserted fact_checks_v2 for fact_check_id=%s", data["fact_check_id"])


# ---------------------------------------------------------------------------
# Crisis classifier / stats extractor — see
# supabase/migrations/0008_crisis_events_and_statistics.sql. Additive to the
# fact_checks / crisis_reports tables above; no dedup, since unlike those two,
# a near-duplicate crisis tag or stat row is cheap and left for the read side
# to de-noise.
# ---------------------------------------------------------------------------


def insert_crisis_event(data: dict) -> Optional[str]:
    """Insert a row into the `crises` table (quick type/severity/tag
    classification — see models.schemas.CrisisEventSchema)."""
    result = get_client().table("crises").insert(data).execute()
    logger.info("Inserted crisis event: %s", data["title"][:80])
    return result.data[0]["id"]


def insert_statistics(rows: list[dict]) -> None:
    """Bulk-insert extracted statistics (`statistics` table)."""
    if not rows:
        return
    get_client().table("statistics").insert(rows).execute()
    logger.info("Inserted %d statistic(s)", len(rows))


# ---------------------------------------------------------------------------
# Public Events — see supabase/migrations/0009_public_events.sql and
# src/pipeline/public_events.py. Dual-written from fact_checks / crisis_reports
# / crises at insert time; upserts on (source_table, source_id) so reruns are
# idempotent instead of producing duplicate rows.
# ---------------------------------------------------------------------------

_IMPORTANCE_BY_SEVERITY = {"low": 20, "medium": 50, "high": 80}


def compute_importance_score(
    *, severity: Optional[str], affects_students: bool, total_outlets: int, source_table: str
) -> int:
    """Deterministic importance_score (0-100) for a public_events row —
    intentionally not AI-guessed (a model free-handing a calibrated 0-100
    number is uncalibrated and inconsistent across calls; see
    supabase/migrations/0009_public_events.sql and the project plan). Built
    only from signals the pipeline already computes: severity (from the
    crisis classifier when present), whether students are affected, real
    media-coverage count (from coverage_analysis via recompute_coverage),
    and whether the source row came from the institutional/RTI-tracking
    crisis_reports table.
    """
    score = _IMPORTANCE_BY_SEVERITY.get(severity or "", 35)
    if affects_students:
        score += 15
    score += 10 * min(total_outlets, 3)
    if source_table == "crisis_reports":
        score += 10
    return max(0, min(100, score))


def insert_public_event(data: dict) -> Optional[str]:
    """Upsert a row into the `public_events` table, keyed on
    (source_table, source_id) so re-processing the same item is a no-op
    update, never a duplicate row."""
    result = (
        get_client()
        .table("public_events")
        .upsert(data, on_conflict="source_table,source_id")
        .execute()
    )
    logger.info("Upserted public event: %s", data["title"][:80])
    return result.data[0]["id"] if result.data else None
