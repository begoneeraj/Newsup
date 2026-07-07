"""General-news Reddit RSS feeds (r/india, r/worldnews) — distinct from
reddit.py's fetch_all_reddit_crises, which hunts for crisis-signal posts in
JEE/NEET-specific subreddits and is always routed to CrisisReportSchema.

These subreddits are general news link-sharing, not crisis-specific, so this
fetcher tags items with source="reddit_news" rather than "reddit" —
classify_content_type in main.py falls through to "fact_check" for any
source other than the literal "reddit", so these are routed the same as
Google News / RSS outlet items instead of polluting the Crisis Tracker.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

REDDIT_RSS_URL = "https://www.reddit.com/r/{subreddit}/.rss"
USER_AGENT = "newsup-accountability-bot/1.0 (by u/newsup_pipeline)"

DEFAULT_SUBREDDITS = ["india", "worldnews"]

_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _parse_feed(subreddit: str, raw_bytes: bytes) -> list[RawContentItem]:
    feed = feedparser.parse(raw_bytes)
    if feed.bozo and not feed.entries:
        logger.warning("Reddit RSS feed failed for r/%s: %s", subreddit, feed.bozo_exception)
        return []

    items: list[RawContentItem] = []
    for entry in feed.entries:
        published_at = None
        if getattr(entry, "published_parsed", None):
            published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

        items.append(
            RawContentItem(
                source="reddit_news",
                origin=f"r/{subreddit}",
                title=entry.get("title", "").strip(),
                text=entry.get("title", "").strip(),
                url=entry.get("link", ""),
                published_at=published_at,
            )
        )
    return items


async def _fetch_one(session: aiohttp.ClientSession, subreddit: str) -> list[RawContentItem]:
    url = REDDIT_RSS_URL.format(subreddit=subreddit)
    headers = {"User-Agent": USER_AGENT}
    try:
        async with session.get(url, headers=headers, timeout=_TIMEOUT) as response:
            raw_bytes = await response.read()
    except aiohttp.ClientError as exc:
        logger.warning("Reddit RSS fetch failed for r/%s: %s", subreddit, exc)
        return []
    return _parse_feed(subreddit, raw_bytes)


async def fetch_all_reddit_news(subreddits: list[str] | None = None) -> list[RawContentItem]:
    """Fetch general-news posts across all target subreddits, concurrently."""
    subreddits = subreddits or DEFAULT_SUBREDDITS
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, sr) for sr in subreddits))
    return [item for batch in results for item in batch]
