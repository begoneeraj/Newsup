"""Per-publisher, per-topic fake-flag track record.

See supabase/migrations/0021_publisher_track_record.sql. One row per
(publisher_name, topic) pair, updated every time an article from that
publisher on that topic is processed by the pipeline.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Optional

from database.supabase_client import get_client

logger = logging.getLogger(__name__)


def get_fake_rate(publisher_name: str, topic: str) -> Optional[float]:
    """Returns the stored fake_rate for this exact (publisher_name, topic)
    pair, or None if no record exists yet (or fake_rate hasn't been computed)."""
    result = (
        get_client()
        .table("publisher_track_record")
        .select("fake_rate")
        .eq("publisher_name", publisher_name)
        .eq("topic", topic)
        .execute()
    )
    return result.data[0]["fake_rate"] if result.data else None


def get_aggregate_fake_rate(publisher_name: str) -> Optional[float]:
    """Returns publisher_name's fake_rate aggregated across ALL topics (sum of
    flagged_fake_count / sum of total_articles), or None if the publisher has
    no track record at all yet. Used where a claim search has no single topic
    to key off of — see ml.corroboration.get_corroboration_score."""
    result = (
        get_client()
        .table("publisher_track_record")
        .select("total_articles, flagged_fake_count")
        .eq("publisher_name", publisher_name)
        .execute()
    )
    if not result.data:
        return None

    total_articles = sum(row["total_articles"] for row in result.data)
    flagged_fake_count = sum(row["flagged_fake_count"] for row in result.data)
    return flagged_fake_count / total_articles if total_articles else None


def update_publisher_record(publisher_name: str, topic: str, was_fake: bool) -> None:
    """Upsert the (publisher_name, topic) row: increments total_articles,
    increments flagged_fake_count if was_fake, and recomputes fake_rate."""
    client = get_client()

    existing = (
        client.table("publisher_track_record")
        .select("total_articles, flagged_fake_count")
        .eq("publisher_name", publisher_name)
        .eq("topic", topic)
        .execute()
    )

    if existing.data:
        row = existing.data[0]
        total_articles = row["total_articles"] + 1
        flagged_fake_count = row["flagged_fake_count"] + (1 if was_fake else 0)
    else:
        total_articles = 1
        flagged_fake_count = 1 if was_fake else 0

    fake_rate = flagged_fake_count / total_articles if total_articles else None

    client.table("publisher_track_record").upsert(
        {
            "publisher_name": publisher_name,
            "topic": topic,
            "total_articles": total_articles,
            "flagged_fake_count": flagged_fake_count,
            "fake_rate": fake_rate,
            "last_updated": datetime.now(timezone.utc).isoformat(),
        },
        on_conflict="publisher_name,topic",
    ).execute()
    logger.info(
        "Updated publisher track record: %s / %s -> %d/%d flagged fake",
        publisher_name,
        topic,
        flagged_fake_count,
        total_articles,
    )
