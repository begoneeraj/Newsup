"""Google News RSS fetcher — no API key, no anti-bot friction.

Fetches all target queries concurrently via aiohttp; feedparser only does the
(sync, CPU-bound) parsing of already-downloaded bytes, never its own network I/O.
"""

from __future__ import annotations

import asyncio
import logging
import re
import urllib.request
from datetime import datetime, timezone
from itertools import zip_longest
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
    # Added alongside the NEET_DAILY_QUOTA gate in main.py: 2 of the 3
    # original queries were NEET/NTA-specific, so NEET dominated the exam
    # feed on the query-generation side as much as the routing side. These
    # give the other tracked exams (see STUDENT_CRISIS_KEYWORDS in main.py)
    # an actual chance of being fetched at all, rather than relying on them
    # showing up incidentally in a NEET-scoped search.
    "JEE Main exam",
    "UPSC exam",
    "CUET exam",
    "GATE exam postponed",
    "CAT exam",
    "CLAT exam",
    "NDA exam",
    "board exam paper leak",
    # Every query above is exam-specific — this source had zero general
    # India/world/crime coverage of its own (the RSS outlets in
    # fetchers/rss_feeds.py were meant to cover that, but two of the three
    # general-news feeds there had dead URLs — see that file's history).
    # Added so this source isn't exam-only by construction.
    "India news",
    "India crime news",
    "world news India",
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
    except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
        logger.warning("Google News fetch failed for query=%r: %s", query, exc)
        return []
    return _parse_feed(query, raw_bytes)


async def fetch_all_google_news(queries: list[str] | None = None) -> list[RawContentItem]:
    """Fetch Google News results across all target queries, concurrently.

    Returns results round-robin interleaved across queries, not concatenated
    query-by-query - a single query commonly returns far more than
    SOURCE_CAPS["google_news"] (main.py) items on its own, and that cap is
    applied to this function's return value by simple list slicing, so a
    concatenated ordering let whichever query happened to be listed first
    (historically "NEET leak") fill the entire per-run cap by itself,
    starving every other query rather than actually diversifying coverage.
    """
    queries = queries or DEFAULT_QUERIES
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, q) for q in queries))
    return [item for group in zip_longest(*results) for item in group if item is not None]


def count_articles(query: str) -> list[dict]:
    """For pipeline.underreported_topics, called via asyncio.to_thread the
    same way fetchers.gdelt.count_articles is (hence synchronous, unlike
    every other function in this file). Named to match that calling
    convention, but Google News RSS has no cheap count-only endpoint the way
    GDELT's article list length serves as one — callers here take len()/a
    slice of the returned list directly instead of getting an int back.
    """
    url = GOOGLE_NEWS_RSS_URL.format(query=quote_plus(query))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            raw_bytes = response.read()
    except Exception:
        logger.exception("Google News count_articles request failed for query=%r", query)
        return []
    items = _parse_feed(query, raw_bytes)
    return [{"title": item.title, "url": item.url} for item in items]
