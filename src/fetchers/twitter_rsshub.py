"""Twitter/X fetcher via RSSHub, for official statements from authorities.

Tries multiple public RSSHub instances in order since any single public
instance can be rate-limited or temporarily down.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

import feedparser
import requests

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

RSSHUB_INSTANCES = [
    "https://rsshub.app",
    "https://rss.shab.fun",
]

DEFAULT_HANDLES = ["dpradhanbjp", "NTA_Exams"]


def fetch_twitter_rsshub(handle: str) -> list[RawContentItem]:
    """Fetch recent tweets for a handle, falling back across RSSHub instances."""
    for base_url in RSSHUB_INSTANCES:
        url = f"{base_url}/twitter/user/{handle}"
        try:
            response = requests.get(url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
            response.raise_for_status()
        except requests.RequestException as exc:
            logger.warning("RSSHub instance %s failed for @%s: %s", base_url, handle, exc)
            continue

        feed = feedparser.parse(response.content)
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


def fetch_all_twitter(handles: list[str] | None = None) -> list[RawContentItem]:
    """Fetch tweets across all target authority handles."""
    handles = handles or DEFAULT_HANDLES
    results: list[RawContentItem] = []
    for handle in handles:
        results.extend(fetch_twitter_rsshub(handle))
    return results
