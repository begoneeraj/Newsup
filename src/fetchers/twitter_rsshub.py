"""Twitter/X fetcher via RSSHub, for official statements from authorities.

Tries multiple public RSSHub instances in order since any single public
instance can be rate-limited or temporarily down. Different handles are
fetched concurrently via aiohttp; the per-handle instance fallback stays
sequential (try instance 1, then instance 2, ...).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

RSSHUB_INSTANCES = [
    "https://rsshub.app",
    "https://rss.shab.fun",
]

DEFAULT_HANDLES = ["dpradhanbjp", "NTA_Exams"]

_TIMEOUT = aiohttp.ClientTimeout(total=15)
_HEADERS = {"User-Agent": "Mozilla/5.0"}


async def _fetch_handle(session: aiohttp.ClientSession, handle: str) -> list[RawContentItem]:
    for base_url in RSSHUB_INSTANCES:
        url = f"{base_url}/twitter/user/{handle}"
        try:
            async with session.get(url, timeout=_TIMEOUT, headers=_HEADERS) as response:
                response.raise_for_status()
                raw_bytes = await response.read()
        except aiohttp.ClientError as exc:
            logger.warning("RSSHub instance %s failed for @%s: %s", base_url, handle, exc)
            continue

        feed = feedparser.parse(raw_bytes)
        if not feed.entries:
            continue

        items: list[RawContentItem] = []
        for entry in feed.entries:
            published_at = None
            if getattr(entry, "published_parsed", None):
                published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

            items.append(
                RawContentItem(
                    source="twitter",
                    origin=f"@{handle}",
                    title=entry.get("title", "").strip(),
                    text=entry.get("summary", entry.get("title", "")).strip(),
                    url=entry.get("link", ""),
                    published_at=published_at,
                )
            )
        return items

    logger.warning("All RSSHub instances failed for @%s", handle)
    return []


async def fetch_all_twitter(handles: list[str] | None = None) -> list[RawContentItem]:
    """Fetch tweets across all target authority handles, concurrently."""
    handles = handles or DEFAULT_HANDLES
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_handle(session, h) for h in handles))
    return [item for batch in results for item in batch]
