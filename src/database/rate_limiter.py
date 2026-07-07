"""Daily quota tracking for metered news APIs (NewsData.io, Mediastack), backed
by rate_limit_tracking (supabase/migrations/0007_rate_limiting_and_headline_hash.sql).

Each source gets one row; the window rolls forward from whenever the first
call after the previous reset happens, not from midnight. Mediastack's quota
is actually monthly, not daily — see fetchers/mediastack.py for how it maps
onto this daily model.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from database.supabase_client import get_client

logger = logging.getLogger(__name__)


def _get_or_create_row(source_name: str, daily_limit: int) -> dict:
    client = get_client()
    result = client.table("rate_limit_tracking").select("*").eq("source_name", source_name).limit(1).execute()
    if result.data:
        return result.data[0]

    inserted = client.table("rate_limit_tracking").insert(
        {
            "source_name": source_name,
            "calls_used": 0,
            "daily_limit": daily_limit,
            "reset_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
        }
    ).execute()
    return inserted.data[0]


def _reset_if_expired(row: dict, daily_limit: int) -> dict:
    reset_at = datetime.fromisoformat(row["reset_at"])
    if datetime.now(timezone.utc) < reset_at:
        return row

    client = get_client()
    updated = client.table("rate_limit_tracking").update(
        {
            "calls_used": 0,
            "daily_limit": daily_limit,
            "reset_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("source_name", row["source_name"]).execute()
    return updated.data[0]


def can_fetch(source_name: str, daily_limit: int) -> bool:
    """True if `source_name` has remaining quota in its current window."""
    row = _reset_if_expired(_get_or_create_row(source_name, daily_limit), daily_limit)
    return row["calls_used"] < daily_limit


def record_request(source_name: str, daily_limit: int, count: int = 1) -> None:
    """Record `count` API calls against `source_name`'s quota."""
    row = _reset_if_expired(_get_or_create_row(source_name, daily_limit), daily_limit)
    get_client().table("rate_limit_tracking").update(
        {
            "calls_used": row["calls_used"] + count,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("source_name", source_name).execute()
    logger.info("%s: %d/%d calls used today", source_name, row["calls_used"] + count, daily_limit)
