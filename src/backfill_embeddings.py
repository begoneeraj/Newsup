"""One-time maintenance script: compute and store embeddings for existing
fact_checks / crisis_reports rows that predate the pgvector migration
(supabase/migrations/0002_pgvector_dedup.sql). Safe to re-run — only rows
with embedding IS NULL are touched.

Run as: python src/backfill_embeddings.py
"""

from __future__ import annotations

import logging

from ai_processor.embeddings import embed_text
from database.supabase_client import get_client

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("newsup.backfill")


def backfill_fact_checks() -> None:
    client = get_client()
    rows = (
        client.table("fact_checks")
        .select("id, claim_text")
        .is_("embedding", "null")
        .execute()
        .data
    )
    logger.info("Backfilling %d fact_checks rows", len(rows))
    for row in rows:
        embedding = embed_text(row["claim_text"])
        client.table("fact_checks").update({"embedding": embedding}).eq("id", row["id"]).execute()
        logger.info("Embedded fact check %s: %s", row["id"], row["claim_text"][:80])


def backfill_crisis_reports() -> None:
    client = get_client()
    rows = (
        client.table("crisis_reports")
        .select("id, title")
        .is_("embedding", "null")
        .execute()
        .data
    )
    logger.info("Backfilling %d crisis_reports rows", len(rows))
    for row in rows:
        embedding = embed_text(row["title"])
        client.table("crisis_reports").update({"embedding": embedding}).eq("id", row["id"]).execute()
        logger.info("Embedded crisis report %s: %s", row["id"], row["title"][:80])


if __name__ == "__main__":
    backfill_fact_checks()
    backfill_crisis_reports()
    logger.info("Backfill complete.")
