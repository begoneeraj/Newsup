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
from itertools import zip_longest

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

DEFAULT_FEEDS = [
    {"name": "PIB India", "url": "https://pib.gov.in/allrss.aspx"},
    # feeds.thehindu.com/feeds.indianexpress.com (the previous URLs here)
    # don't resolve at all (DNS failure, confirmed on every single news_cron
    # run's logs) - these two outlets carry most of this pipeline's general
    # India news/crime/politics coverage (NEET/JEE/etc. search queries are
    # the only other India-scoped source), so they'd been silently
    # contributing zero articles, every run, for as long as these URLs have
    # been wrong. Re-verified live against thehindu.com/indianexpress.com's
    # own site-hosted feeds before swapping in.
    {"name": "The Hindu", "url": "https://www.thehindu.com/news/national/feeder/default.rss"},
    {"name": "Indian Express", "url": "https://indianexpress.com/section/india/feed/"},
    {"name": "BBC World", "url": "http://feeds.bbci.co.uk/news/world/rss.xml"},
    # Confirmed live before adding — mixes research write-ups with general
    # science journalism, so unlike fetchers/arxiv.py (unambiguous by
    # source), these still need keyword routing to reach science_research.
    {"name": "The Hindu Science", "url": "https://www.thehindu.com/sci-tech/science/feeder/default.rss"},
    # International outlets added to broaden coverage beyond India-scoped
    # sources above — every URL here was curl-verified live (200, real RSS
    # body) before adding. Reuters' public feed URLs
    # (reutersagency.com/feed/?best-topics=...) are NOT included: Reuters
    # discontinued public RSS years ago and every variant of that URL
    # 404s — don't re-add without first verifying a working replacement.
    {"name": "BBC News", "url": "http://feeds.bbci.co.uk/news/rss.xml"},
    {"name": "BBC Technology", "url": "http://feeds.bbci.co.uk/news/technology/rss.xml"},
    {"name": "BBC Business", "url": "http://feeds.bbci.co.uk/news/business/rss.xml"},
    {"name": "CNN Top Stories", "url": "http://rss.cnn.com/rss/cnn_topstories.rss"},
    {"name": "CNN World", "url": "http://rss.cnn.com/rss/cnn_world.rss"},
    {"name": "CNN Tech", "url": "http://rss.cnn.com/rss/cnn_tech.rss"},
    {"name": "NY Times Home", "url": "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"},
    {"name": "NY Times Technology", "url": "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml"},
    {"name": "NY Times Business", "url": "https://rss.nytimes.com/services/xml/rss/nyt/Business.xml"},
    {"name": "Al Jazeera", "url": "https://www.aljazeera.com/xml/rss/all.xml"},
    {"name": "The Guardian World", "url": "https://www.theguardian.com/world/rss"},
    {"name": "The Guardian US", "url": "https://www.theguardian.com/us/rss"},
    {"name": "TechCrunch", "url": "https://techcrunch.com/feed/"},
    {"name": "Wired", "url": "https://www.wired.com/feed/rss"},
    {"name": "Hacker News", "url": "https://hnrss.org/frontpage"},
]

_TAG_RE = re.compile(r"<[^>]+>")
_TIMEOUT = aiohttp.ClientTimeout(total=15)
# Al Jazeera's edge (Akamai) returns 403 Access Denied to requests with no
# User-Agent header at all (confirmed: aiohttp's default, empty UA, fails;
# any browser-like UA succeeds) — same UA string fetchers/google_news.py's
# count_articles already uses for the same reason. Sent to every feed, not
# just Al Jazeera's, since a harmless UA doesn't hurt outlets that don't care.
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}


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
        async with session.get(feed["url"], timeout=_TIMEOUT, headers=_HEADERS) as response:
            raw_bytes = await response.read()
    except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
        logger.warning("RSS fetch failed for outlet=%r: %s", feed["name"], exc)
        return []
    return _parse_feed(feed["name"], raw_bytes)


async def fetch_all_rss_outlets(feeds: list[dict] | None = None) -> list[RawContentItem]:
    """Fetch all configured direct-outlet RSS feeds, concurrently.

    Round-robin interleaved across feeds (not concatenated feed-by-feed) —
    same reasoning as fetchers/google_news.py's fetch_all_google_news: this
    list now spans 18 outlets, each easily returning 20-50 entries, while
    main.py's SOURCE_CAPS["rss_outlets"] slices the return value down to a
    small per-run share. Concatenating would let whichever feed is listed
    first (previously PIB India) fill that entire cap by itself, silently
    starving every other outlet.
    """
    feeds = feeds or DEFAULT_FEEDS
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, feed) for feed in feeds))
    return [item for group in zip_longest(*results) for item in group if item is not None]


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
