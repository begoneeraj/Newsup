"""Google News RSS fetcher — no API key, no anti-bot friction.

Fetches all target queries concurrently via aiohttp; feedparser only does the
(sync, CPU-bound) parsing of already-downloaded bytes, never its own network I/O.
"""

from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import quote_plus

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

GOOGLE_NEWS_RSS_URL = (
    "https://news.google.com/rss/search?q={query}&hl=en-IN&gl=IN&ceid=IN:en"
)

DEFAULT_QUERIES = [
    "NEET leak",
    "NTA scam",
    "Education Minister student protest",
]

_TAG_RE = re.compile(r"<[^>]+>")
_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _strip_html(raw: str) -> str:
    return _TAG_RE.sub(" ", raw).strip()


def _extract_outlet_name(entry, title: str) -> Optional[str]:
    """Google News RSS <source> tags carry the actual publisher name. Fall
    back to the " - Publisher" suffix Google News titles are formatted with
    when a feed doesn't include the tag (feedparser still exposes it as
    entry.source.title when present)."""
    source = entry.get("source")
    if source and source.get("title"):
        return source["title"].strip()

    if " - " in title:
        return title.rsplit(" - ", 1)[1].strip()

    return None


def _parse_feed(query: str, raw_bytes: bytes) -> list[RawContentItem]:
    feed = feedparser.parse(raw_bytes)
    if feed.bozo and not feed.entries:
        logger.warning("Google News feed failed for query=%r: %s", query, feed.bozo_exception)
        return []

    items: list[RawContentItem] = []
    for entry in feed.entries:
        published_at = None
        if getattr(entry, "published_parsed", None):
            published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

        title = entry.get("title", "").strip()
        items.append(
            RawContentItem(
                source="google_news",
                origin=query,
                title=title,
                text=_strip_html(entry.get("summary", "")),
                url=entry.get("link", ""),
                published_at=published_at,
                outlet_name=_extract_outlet_name(entry, title),
            )
        )
    return items


async def _fetch_one(session: aiohttp.ClientSession, query: str) -> list[RawContentItem]:
    url = GOOGLE_NEWS_RSS_URL.format(query=quote_plus(query))
    try:
        async with session.get(url, timeout=_TIMEOUT) as response:
            raw_bytes = await response.read()
    except aiohttp.ClientError as exc:
        logger.warning("Google News fetch failed for query=%r: %s", query, exc)
        return []
    return _parse_feed(query, raw_bytes)


async def fetch_all_google_news(queries: list[str] | None = None) -> list[RawContentItem]:
    """Fetch Google News results across all target queries, concurrently."""
    queries = queries or DEFAULT_QUERIES
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, q) for q in queries))
    return [item for batch in results for item in batch]
