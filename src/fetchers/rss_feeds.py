"""Direct outlet RSS feeds — unlike google_news.py's search-query feeds, each
of these belongs to a single named publisher, so outlet_name is known
statically per feed rather than parsed out of the entry.

Fetches all feeds concurrently via aiohttp; feedparser only does the (sync,
CPU-bound) parsing of already-downloaded bytes, never its own network I/O —
same split as google_news.py.
"""

from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timezone

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

DEFAULT_FEEDS = [
    {"name": "PIB India", "url": "https://pib.gov.in/allrss.aspx"},
    {"name": "The Hindu", "url": "https://feeds.thehindu.com/news/national/"},
    {"name": "Indian Express", "url": "https://feeds.indianexpress.com/news/"},
    # Dead as of this writing (404) — see fetchers/prs_legislative.py for
    # the real scraper that replaced this feed's role.
    {"name": "PRS Legislative", "url": "https://www.prsindia.org/rss"},
    {"name": "BBC World", "url": "http://feeds.bbci.co.uk/news/world/rss.xml"},
    # Confirmed live before adding — mixes research write-ups with general
    # science journalism, so unlike fetchers/arxiv.py (unambiguous by
    # source), these still need keyword routing to reach science_research.
    {"name": "The Hindu Science", "url": "https://www.thehindu.com/sci-tech/science/feeder/default.rss"},
]

_TAG_RE = re.compile(r"<[^>]+>")
_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _strip_html(raw: str) -> str:
    return _TAG_RE.sub(" ", raw).strip()


def _parse_feed(outlet_name: str, raw_bytes: bytes) -> list[RawContentItem]:
    feed = feedparser.parse(raw_bytes)
    if feed.bozo and not feed.entries:
        logger.warning("RSS feed failed for outlet=%r: %s", outlet_name, feed.bozo_exception)
        return []

    items: list[RawContentItem] = []
    for entry in feed.entries:
        published_at = None
        if getattr(entry, "published_parsed", None):
            published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

        items.append(
            RawContentItem(
                source="rss_outlet",
                origin=outlet_name,
                title=entry.get("title", "").strip(),
                text=_strip_html(entry.get("summary", "")),
                url=entry.get("link", ""),
                published_at=published_at,
                outlet_name=outlet_name,
            )
        )
    return items


async def _fetch_one(session: aiohttp.ClientSession, feed: dict) -> list[RawContentItem]:
    try:
        async with session.get(feed["url"], timeout=_TIMEOUT) as response:
            raw_bytes = await response.read()
    except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
        logger.warning("RSS fetch failed for outlet=%r: %s", feed["name"], exc)
        return []
    return _parse_feed(feed["name"], raw_bytes)


async def fetch_all_rss_outlets(feeds: list[dict] | None = None) -> list[RawContentItem]:
    """Fetch all configured direct-outlet RSS feeds, concurrently."""
    feeds = feeds or DEFAULT_FEEDS
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, feed) for feed in feeds))
    return [item for batch in results for item in batch]


# Kept as its own fetcher/source (rather than folded into DEFAULT_FEEDS
# above) so it gets its own SOURCE_CAPS entry in main.py instead of sharing
# rss_outlets' combined cap — BusinessLine is treated as higher-signal for
# India policy/science coverage than the general rss_outlets bucket.
BUSINESSLINE_FEED = {
    "name": "The Hindu BusinessLine",
    "url": "https://www.thehindubusinessline.com/feeder/default.rss",
}


async def fetch_all_businessline() -> list[RawContentItem]:
    """Fetch The Hindu BusinessLine's RSS feed. Same fetch/parse path as
    fetch_all_rss_outlets, just scoped to a single feed."""
    async with aiohttp.ClientSession() as session:
        return await _fetch_one(session, BUSINESSLINE_FEED)
