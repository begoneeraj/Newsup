"""NewsData.io fetcher — https://newsdata.io/, free tier (verify the current
quota on your dashboard; NEWSDATA_DAILY_LIMIT defaults to a conservative 180
to leave headroom below the commonly-cited 200/day free-tier cap).

Rate-limited via database.rate_limiter so a quota exhaustion mid-run stops
further calls instead of erroring, and picks back up on the next cron run.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone

import aiohttp

from database.rate_limiter import can_fetch, record_request
from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

NEWSDATA_URL = "https://newsdata.io/api/1/news"
SOURCE_NAME = "newsdata"
DAILY_LIMIT = int(os.environ.get("NEWSDATA_DAILY_LIMIT", "180"))

DEFAULT_QUERIES = [
    "NEET",
    "education ministry India",
]

_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _parse_published_at(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        # NewsData returns "YYYY-MM-DD HH:MM:SS" (UTC, no offset marker).
        return datetime.fromisoformat(raw).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


async def fetch_all_newsdata(queries: list[str] | None = None) -> list[RawContentItem]:
    api_key = os.environ.get("NEWSDATA_API_KEY")
    if not api_key:
        logger.warning("NEWSDATA_API_KEY not set; skipping NewsData fetch")
        return []

    queries = queries or DEFAULT_QUERIES
    items: list[RawContentItem] = []

    async with aiohttp.ClientSession() as session:
        for query in queries:
            if not can_fetch(SOURCE_NAME, DAILY_LIMIT):
                logger.warning("NewsData daily quota exhausted; stopping early")
                break

            try:
                async with session.get(
                    NEWSDATA_URL,
                    params={"apikey": api_key, "q": query, "country": "in", "language": "en"},
                    timeout=_TIMEOUT,
                ) as response:
                    record_request(SOURCE_NAME, DAILY_LIMIT)
                    payload = await response.json()
            except aiohttp.ClientError as exc:
                logger.warning("NewsData fetch failed for query=%r: %s", query, exc)
                continue

            if payload.get("status") != "success":
                logger.warning("NewsData returned non-success for query=%r: %s", query, payload.get("message"))
                continue

            for article in payload.get("results") or []:
                items.append(
                    RawContentItem(
                        source="newsdata",
                        origin=query,
                        title=(article.get("title") or "").strip(),
                        text=(article.get("description") or "").strip(),
                        url=article.get("link", ""),
                        published_at=_parse_published_at(article.get("pubDate")),
                        outlet_name=article.get("source_id"),
                    )
                )

    logger.info("NewsData: fetched %d articles across %d queries", len(items), len(queries))
    return items
