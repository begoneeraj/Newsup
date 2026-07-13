"""Supabase client and deduplicating upsert logic for fact_checks / crisis_reports."""

from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone
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


# ---------------------------------------------------------------------------
# Cross-outlet dedup for public_events — the (source_table, source_id) upsert
# above only stops the *same* fact_check/crisis_report/crisis row from being
# written twice. It does nothing when two *different* rows (e.g. two outlets'
# separately-classified articles) describe the same real-world event, which
# is the actual cause of duplicate cards in Crisis Tracker. See
# src/pipeline/public_events.py::find_or_merge_public_event and
# src/utils/fuzzy_match.py.
# ---------------------------------------------------------------------------

_MERGE_LOOKBACK_DAYS = {
    # Exam issues develop slowly (leak -> investigation -> postponement can
    # span weeks); disasters/violence are acute and shouldn't merge with an
    # unrelated event that happens to recur months later.
    "exam_leak": 14,
    "exam_delay": 14,
}
_DEFAULT_MERGE_LOOKBACK_DAYS = 4

_SEVERITY_ESCALATION_THRESHOLDS = [(6, "high"), (3, "medium")]


def merge_lookback_days(event_type: str) -> int:
    return _MERGE_LOOKBACK_DAYS.get(event_type, _DEFAULT_MERGE_LOOKBACK_DAYS)


def find_recent_public_events(
    event_type: str, state: Optional[str], since_iso: str, limit: int = 25
) -> list[dict]:
    """Small candidate set for fuzzy title matching — same event_type,
    not already resolved, updated within the merge window, optionally
    narrowed to the same state. Deliberately cheap: callers fuzzy-match
    titles client-side rather than pushing similarity into SQL.

    Includes the *_sources buckets (not just the row's own `title`) so a
    caller can fuzzy-match a new headline against every headline already
    merged into a card, not just its original title — without this, a
    card's comparable title never updates, and enough successive
    differently-worded merges can drift the new headline out of similarity
    range of the original one even though it's still the same event.
    """
    query = (
        get_client()
        .table("public_events")
        .select(
            "id,title,merge_count,severity,"
            "official_sources,media_sources,reddit_sources,youtube_sources"
        )
        .eq("event_type", event_type)
        .neq("status", "resolved")
        .gte("last_updated", since_iso)
        .order("last_updated", desc=True)
        .limit(limit)
    )
    if state:
        query = query.eq("state", state)
    result = query.execute()
    return result.data or []


def _escalate_severity(current: Optional[str], merge_count: int) -> Optional[str]:
    for count_threshold, escalated in _SEVERITY_ESCALATION_THRESHOLDS:
        if merge_count >= count_threshold:
            severity_rank = {"low": 0, "medium": 1, "high": 2}
            if severity_rank.get(current or "low", 0) < severity_rank[escalated]:
                return escalated
    return current


def merge_public_event(existing_id: str, bucket: str, new_entry: dict) -> None:
    """Fold a new source into an existing public_events row instead of
    inserting a duplicate card: appends `new_entry` to the given
    `*_sources` jsonb bucket, bumps merge_count, escalates severity once
    enough independent sources have corroborated the event, and refreshes
    last_updated."""
    client = get_client()
    row = client.table("public_events").select(f"{bucket},merge_count,severity").eq("id", existing_id).single().execute()
    existing_bucket = (row.data or {}).get(bucket) or []
    merge_count = ((row.data or {}).get("merge_count") or 1) + 1
    severity = _escalate_severity((row.data or {}).get("severity"), merge_count)

    client.table("public_events").update(
        {
            bucket: [*existing_bucket, new_entry],
            "merge_count": merge_count,
            "severity": severity,
            "last_updated": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("id", existing_id).execute()
    logger.info("Merged new source into public event %s (merge_count=%d)", existing_id, merge_count)


def find_recent_crisis_titles(since_iso: str, limit: int = 50) -> list[dict]:
    """Candidate set for the fuzzy pre-check in main.py::process_new_taxonomies,
    run before spending a crisis-classification Groq call. event_type isn't
    known yet at this point (that's what the Groq call determines), so this
    intentionally doesn't filter by type — just recency — and relies on
    title_similarity to do the filtering."""
    result = (
        get_client()
        .table("crises")
        .select("id,title")
        .neq("status", "resolved")
        .gte("created_at", since_iso)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


def bump_crisis_report(existing_id: str) -> None:
    """crises-table equivalent of merge_public_event's counter/severity
    logic — used when a fuzzy title match on the crises route means a fresh
    Groq classification call can be skipped entirely (see
    main.py::process_new_taxonomies)."""
    client = get_client()
    row = client.table("crises").select("report_count,severity").eq("id", existing_id).single().execute()
    report_count = ((row.data or {}).get("report_count") or 1) + 1
    severity = _escalate_severity((row.data or {}).get("severity"), report_count)
    client.table("crises").update(
        {
            "report_count": report_count,
            "severity": severity,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("id", existing_id).execute()
    logger.info("Bumped crisis report count for %s (report_count=%d)", existing_id, report_count)


# ---------------------------------------------------------------------------
# Expansion modules — student crisis / AI & tech / govt promises / court
# cases. See truthlens_expansion_prompt.md Parts 1-6 and
# supabase/migrations/0012_expansion_modules.sql. Additive: independent of
# every table above.
#
# student_crisis_reports and ai_tech_reports are one-shot articles (plain
# insert, deduped by headline_hash like `crises`/`statistics`).
# govt_promises and court_cases are living records that get updated as a
# project/case progresses, so they use the manual select-then-update/insert
# pattern from Part 6 of the spec, keyed on project_slug/case_slug.
# ---------------------------------------------------------------------------


def student_crisis_report_exists(headline_hash: str) -> bool:
    return find_by_headline_hash("student_crisis_reports", headline_hash) is not None


def insert_student_crisis_report(data: dict) -> Optional[str]:
    """Insert a student_crisis_reports row, skipping if a duplicate
    headline_hash already exists."""
    headline_hash = data.get("headline_hash")
    if headline_hash and student_crisis_report_exists(headline_hash):
        logger.info("Skipping duplicate student crisis report: %s", data.get("headline_plain", "")[:80])
        return None

    result = get_client().table("student_crisis_reports").insert(data).execute()
    logger.info("Inserted student crisis report: %s", data.get("headline_plain", "")[:80])
    return result.data[0]["id"] if result.data else None


def count_recent_student_crisis_reports(exam_keyword: str, hours: int = 24) -> int:
    """Used by main.py's NEET daily quota check. Matches on exam_or_context
    text (ilike) rather than a taxonomy column - there's no exam_type enum
    on student_crisis_reports, and exam_or_context is free text Groq writes
    per article, same "match on text, not a taxonomy" philosophy
    main._keyword_matches already uses for routing."""
    since_iso = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
    result = (
        get_client()
        .table("student_crisis_reports")
        .select("id", count="exact")
        .ilike("exam_or_context", f"%{exam_keyword}%")
        .gte("processed_at", since_iso)
        .execute()
    )
    return result.count or 0


def ai_tech_report_exists(headline_hash: str) -> bool:
    return find_by_headline_hash("ai_tech_reports", headline_hash) is not None


def insert_ai_tech_report(data: dict) -> Optional[str]:
    """Insert an ai_tech_reports row, skipping if a duplicate headline_hash
    already exists."""
    headline_hash = data.get("headline_hash")
    if headline_hash and ai_tech_report_exists(headline_hash):
        logger.info("Skipping duplicate AI/tech report: %s", data.get("headline_plain", "")[:80])
        return None

    result = get_client().table("ai_tech_reports").insert(data).execute()
    logger.info("Inserted AI/tech report: %s", data.get("headline_plain", "")[:80])
    return result.data[0]["id"] if result.data else None


def science_research_report_exists(headline_hash: str) -> bool:
    return find_by_headline_hash("science_research_reports", headline_hash) is not None


def insert_science_research_report(data: dict) -> Optional[str]:
    """Insert a science_research_reports row, skipping if a duplicate
    headline_hash already exists - same one-shot-article convention as
    insert_ai_tech_report/insert_student_crisis_report."""
    headline_hash = data.get("headline_hash")
    if headline_hash and science_research_report_exists(headline_hash):
        logger.info("Skipping duplicate science research report: %s", data.get("headline_plain", "")[:80])
        return None

    result = get_client().table("science_research_reports").insert(data).execute()
    logger.info("Inserted science research report: %s", data.get("headline_plain", "")[:80])
    return result.data[0]["id"] if result.data else None


def upsert_govt_promise(data: dict) -> Optional[str]:
    """Part 6 of the spec: govt_promises are living records, deduplicated
    on project_slug rather than a one-time headline_hash insert. Updates
    the mutable fields on an existing project, inserts a new row otherwise."""
    client = get_client()
    slug = data.get("project_slug")
    if not slug:
        return None

    existing = client.table("govt_promises").select("id").eq("project_slug", slug).execute()

    if existing.data:
        row_id = existing.data[0]["id"]
        update_fields = {
            "current_status": data["current_status"],
            "headline_plain": data["headline_plain"],
            "ai_summary": data["ai_summary"],
            "genz_summary": data.get("genz_summary"),
            "broken_promise_flag": data["broken_promise_flag"],
            "broken_promise_detail": data.get("broken_promise_detail"),
            "revised_completion_date": data.get("revised_completion_date"),
            "budget_spent_crore": data.get("budget_spent_crore"),
            "next_milestone": data.get("next_milestone"),
            "key_facts": data.get("key_facts", []),
            "last_updated": datetime.now(timezone.utc).isoformat(),
        }
        # party/election_year are only ever known from election_promise
        # articles (see _GOVT_PROMISE_SYSTEM_PROMPT: "leave null rather than
        # guessing") - a routine non-election update legitimately returns
        # null for these, and must not clobber a value a manifesto backfill
        # or earlier article already established.
        if data.get("party") is not None:
            update_fields["party"] = data["party"]
        if data.get("election_year") is not None:
            update_fields["election_year"] = data["election_year"]

        client.table("govt_promises").update(update_fields).eq("project_slug", slug).execute()
        logger.info("Updated govt promise %s (%s)", row_id, slug)
        return row_id

    result = client.table("govt_promises").insert(data).execute()
    logger.info("Inserted govt promise: %s", slug)
    return result.data[0]["id"] if result.data else None


def fetch_govt_promise_match_candidates() -> list[dict]:
    """Slim projection used by pipeline.promise_evidence's fuzzy-match
    against incoming PRS/eLibrary articles - just enough fields to score a
    title match and, if matched, run the Stage B stance call. Excludes
    cancelled promises, same as fetch_promises_needing_reverification."""
    result = (
        get_client()
        .table("govt_promises")
        .select("id, project_name, official_claim")
        .neq("current_status", "cancelled")
        .execute()
    )
    return result.data or []


def insert_promise_evidence(data: dict) -> Optional[str]:
    """promise_evidence is append-only (see migration 0013) - every match
    against a tracked promise gets its own row, unlike govt_promises'
    update-in-place convention above."""
    result = get_client().table("promise_evidence").insert(data).execute()
    logger.info("Inserted promise evidence for promise_id=%s", data.get("promise_id"))
    return result.data[0]["id"] if result.data else None


def fetch_promise_evidence(promise_id: str) -> list[dict]:
    result = (
        get_client()
        .table("promise_evidence")
        .select("*")
        .eq("promise_id", promise_id)
        .order("observed_at", desc=True)
        .execute()
    )
    return result.data or []


def fetch_promises_needing_reverification() -> list[dict]:
    """Candidates for the weekly Stage D job: anything not cancelled that
    has never been verified, or has promise_evidence newer than its last
    verification pass. The evidence-freshness half of that filter is
    cheaper to apply in Python than in a single Supabase query (would need
    a correlated subquery), so this returns the never-verified set plus
    every non-cancelled promise; the caller (pipeline.promise_reverification)
    cross-references each candidate's evidence timestamps against
    last_verified_at before spending a Groq call on it."""
    result = (
        get_client()
        .table("govt_promises")
        .select("*")
        .neq("current_status", "cancelled")
        .execute()
    )
    return result.data or []


def update_promise_verification(promise_id: str, data: dict) -> None:
    """Writes Stage D's output (see
    ai_processor.groq_processor.process_govt_promise_reverification) back
    onto the existing govt_promises row, keyed on id (not project_slug -
    the caller already has the row)."""
    get_client().table("govt_promises").update(
        {
            "implementation_quality": data["implementation_quality"],
            "verification_confidence": data["verification_confidence"],
            "official_claim": data["official_claim"],
            "ground_reality": data["ground_reality"],
            "current_status": data["current_status"],
            "broken_promise_flag": data["broken_promise_flag"],
            "broken_promise_detail": data.get("broken_promise_detail"),
            "last_verified_at": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("id", promise_id).execute()
    logger.info("Updated verification for govt promise %s", promise_id)


def upsert_court_case(data: dict) -> Optional[str]:
    """Part 6 of the spec: court_cases are living records, deduplicated on
    case_slug rather than a one-time headline_hash insert. Updates the
    mutable hearing/order fields on an existing case, inserts a new row
    otherwise."""
    client = get_client()
    slug = data.get("case_slug")
    if not slug:
        return None

    existing = client.table("court_cases").select("id").eq("case_slug", slug).execute()

    if existing.data:
        row_id = existing.data[0]["id"]
        client.table("court_cases").update(
            {
                "last_hearing_date": data.get("last_hearing_date"),
                "last_hearing_outcome": data.get("last_hearing_outcome"),
                "next_hearing_date": data.get("next_hearing_date"),
                "current_order": data.get("current_order"),
                "respondent_argument": data.get("respondent_argument"),
                "headline_plain": data["headline_plain"],
                "ai_summary": data["ai_summary"],
                "key_facts": data.get("key_facts", []),
                "last_updated": datetime.now(timezone.utc).isoformat(),
            }
        ).eq("case_slug", slug).execute()
        logger.info("Updated court case %s (%s)", row_id, slug)
        return row_id

    result = client.table("court_cases").insert(data).execute()
    logger.info("Inserted court case: %s", slug)
    return result.data[0]["id"] if result.data else None


# ---------------------------------------------------------------------------
# Slow Crises module. slow_crises is a living record (keyed on crisis_slug,
# same select-then-update/insert pattern as govt_promises/court_cases above)
# whose current_severity is computed by pure code
# (pipeline.slow_crisis_quant._compute_severity) from crisis_data_points -
# never by Groq. crisis_narrative_updates (Track 2) is a one-shot,
# headline_hash-deduped child row like student_crisis_reports.
# ---------------------------------------------------------------------------


def get_or_create_slow_crisis(data: dict) -> str:
    """Returns the id of the slow_crises row for data['crisis_slug'],
    creating it with the given fields if it doesn't exist yet. Unlike
    upsert_govt_promise, this never updates an existing row's descriptive
    fields (title/description/etc.) - only
    update_slow_crisis_severity below ever mutates an existing row, and
    only current_severity/last_computed_at."""
    client = get_client()
    slug = data["crisis_slug"]
    existing = client.table("slow_crises").select("id").eq("crisis_slug", slug).execute()
    if existing.data:
        return existing.data[0]["id"]

    result = client.table("slow_crises").insert(data).execute()
    logger.info("Created slow crisis: %s", slug)
    return result.data[0]["id"]


def update_slow_crisis_severity(crisis_id: str, severity: str) -> None:
    get_client().table("slow_crises").update(
        {
            "current_severity": severity,
            "last_computed_at": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("id", crisis_id).execute()
    logger.info("Updated slow crisis %s severity=%s", crisis_id, severity)


def insert_crisis_data_point(data: dict) -> Optional[str]:
    """crisis_data_points is append-only - every Track 1 reading gets its
    own row, same pattern as promise_evidence."""
    result = get_client().table("crisis_data_points").insert(data).execute()
    return result.data[0]["id"] if result.data else None


def fetch_recent_crisis_data_points(crisis_id: str, limit: int = 30) -> list[dict]:
    """Returns readings oldest-first (ascending) since
    pipeline.slow_crisis_quant._compute_severity assumes that ordering when
    comparing recent vs. previous trend windows."""
    result = (
        get_client()
        .table("crisis_data_points")
        .select("value,unit,recorded_date")
        .eq("crisis_id", crisis_id)
        .order("recorded_date", desc=True)
        .limit(limit)
        .execute()
    )
    return list(reversed(result.data or []))


def crisis_narrative_update_exists(headline_hash: str) -> bool:
    return find_by_headline_hash("crisis_narrative_updates", headline_hash) is not None


def insert_crisis_narrative_update(data: dict) -> Optional[str]:
    headline_hash = data.get("headline_hash")
    if headline_hash and crisis_narrative_update_exists(headline_hash):
        logger.info("Skipping duplicate crisis narrative update (headline hash match)")
        return None

    result = get_client().table("crisis_narrative_updates").insert(data).execute()
    logger.info("Inserted crisis narrative update for crisis_id=%s", data.get("crisis_id"))
    return result.data[0]["id"] if result.data else None


def fetch_all_slow_crises() -> list[dict]:
    """Slim projection for pipeline.slow_crisis_narrative's fuzzy-match
    against incoming articles - mirrors
    fetch_govt_promise_match_candidates."""
    result = get_client().table("slow_crises").select("id, title, category").execute()
    return result.data or []


def data_story_exists(headline_hash: str) -> bool:
    return find_by_headline_hash("data_stories", headline_hash) is not None


def insert_data_story(data: dict) -> Optional[str]:
    """Insert a data_stories row, skipping if a duplicate headline_hash
    already exists - same one-shot convention as
    insert_science_research_report."""
    headline_hash = data.get("headline_hash")
    if headline_hash and data_story_exists(headline_hash):
        logger.info("Skipping duplicate data story: %s", data.get("title", "")[:80])
        return None

    result = get_client().table("data_stories").insert(data).execute()
    logger.info("Inserted data story: %s", data.get("title", "")[:80])
    return result.data[0]["id"] if result.data else None
