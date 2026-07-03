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


def insert_fact_check(data: dict) -> bool:
    """Insert a fact check row, skipping if a duplicate already exists.

    Returns True if a row was inserted, False if skipped as a duplicate.
    """
    if fact_check_exists(data["claim_text"], data.get("source_url", "")):
        logger.info("Skipping duplicate fact check: %s", data["claim_text"][:80])
        return False

    get_client().table("fact_checks").insert(data).execute()
    logger.info("Inserted fact check: %s", data["claim_text"][:80])
    return True


def insert_crisis_report(data: dict) -> bool:
    """Insert a crisis report row, skipping if a duplicate already exists.

    Returns True if a row was inserted, False if skipped as a duplicate.
    """
    if crisis_report_exists(data["title"], data.get("source_url", "")):
        logger.info("Skipping duplicate crisis report: %s", data["title"][:80])
        return False

    get_client().table("crisis_reports").insert(data).execute()
    logger.info("Inserted crisis report: %s", data["title"][:80])
    return True
