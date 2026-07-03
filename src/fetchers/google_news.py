"""Google News RSS fetcher — no API key, no anti-bot friction."""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from urllib.parse import quote_plus

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


def _strip_html(raw: str) -> str:
    return _TAG_RE.sub(" ", raw).strip()


def fetch_google_news(query: str) -> list[RawContentItem]:
    """Fetch and parse the Google News RSS feed for a single search query."""
    url = GOOGLE_NEWS_RSS_URL.format(query=quote_plus(query))
    feed = feedparser.parse(url)

    if feed.bozo and not feed.entries:
        logger.warning("Google News feed failed for query=%r: %s", query, feed.bozo_exception)
        return []

    items: list[RawContentItem] = []
    for entry in feed.entries:
        published_at = None
        if getattr(entry, "published_parsed", None):
            published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

        items.append(
            RawContentItem(
                source="google_news",
                origin=query,
                title=entry.get("title", "").strip(),
                text=_strip_html(entry.get("summary", "")),
                url=entry.get("link", ""),
                published_at=published_at,
            )
        )
    return items


def fetch_all_google_news(queries: list[str] | None = None) -> list[RawContentItem]:
    """Fetch Google News results across all target queries."""
    queries = queries or DEFAULT_QUERIES
    results: list[RawContentItem] = []
    for query in queries:
        results.extend(fetch_google_news(query))
    return results
