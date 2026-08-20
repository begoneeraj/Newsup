"""The Guardian Open Platform fetcher — https://open-platform.theguardian.com/.
Free "developer" tier: 12 calls/second, 5000 calls/day (verify against your
own key's dashboard). Structured JSON, no RSS parsing needed, so this covers
the same World/US/Tech ground as the Guardian RSS feeds in rss_feeds.py but
with a real API (pagination, section filtering) instead of a fixed feed.
"""

from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime, timezone
from itertools import zip_longest

import aiohttp

from database.rate_limiter import can_fetch, record_request
from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

GUARDIAN_URL = "https://content.guardianapis.com/search"
SOURCE_NAME = "guardian"
DAILY_LIMIT = int(os.environ.get("GUARDIAN_DAILY_LIMIT", "400"))

# One entry per Guardian section — kept separate (rather than one
# section=world|us-news|technology query) and interleaved below, same
# reasoning as google_news.py's per-query round-robin: a single combined
# query would let whichever section the API returns first dominate the
# per-run cap.
DEFAULT_SECTIONS = ["world", "us-news", "technology", "business"]

_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _parse_published_at(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


async def _fetch_section(
    session: aiohttp.ClientSession, api_key: str, section: str
) -> list[RawContentItem]:
    if not can_fetch(SOURCE_NAME, DAILY_LIMIT):
        logger.warning("Guardian daily quota exhausted; skipping section=%r", section)
        return []

    try:
        async with session.get(
            GUARDIAN_URL,
            params={
                "api-key": api_key,
                "section": section,
                "page-size": 20,
                "order-by": "newest",
                "show-fields": "trailText",
            },
            timeout=_TIMEOUT,
        ) as response:
            record_request(SOURCE_NAME, DAILY_LIMIT)
            # Guardian's Content-Type header doesn't reliably include
            # charset=utf-8 (confirmed: it's absent on some responses,
            # present on others) — without forcing utf-8, aiohttp's encoding
            # guess mangles curly quotes/em dashes in titles into "�".
            payload = await response.json(encoding="utf-8")
    except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
        logger.warning("Guardian fetch failed for section=%r: %s", section, exc)
        return []

    if payload.get("response", {}).get("status") != "ok":
        logger.warning("Guardian returned non-ok status for section=%r: %s", section, payload)
        return []

    items: list[RawContentItem] = []
    for result in payload["response"].get("results") or []:
        title = (result.get("webTitle") or "").strip()
        items.append(
            RawContentItem(
                source="guardian",
                origin=f"guardian:{section}",
                title=title,
                text=(result.get("fields", {}).get("trailText") or "").strip(),
                url=result.get("webUrl", ""),
                published_at=_parse_published_at(result.get("webPublicationDate")),
                outlet_name="The Guardian",
            )
        )
    return items


async def fetch_all_guardian(sections: list[str] | None = None) -> list[RawContentItem]:
    """Fetch The Guardian across all target sections, concurrently.
    Round-robin interleaved across sections — same reasoning as
    fetch_all_google_news, so SOURCE_CAPS's per-run slice doesn't let
    whichever section is listed first crowd out the rest.
    """
    api_key = os.environ.get("THE_GUARDIAN_API_KEY")
    if not api_key:
        logger.warning("THE_GUARDIAN_API_KEY not set; skipping Guardian fetch")
        return []

    sections = sections or DEFAULT_SECTIONS
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(
            *(_fetch_section(session, api_key, section) for section in sections)
        )
    items = [item for group in zip_longest(*results) for item in group if item is not None]
    logger.info("Guardian: fetched %d articles across %d sections", len(items), len(sections))
    return items
