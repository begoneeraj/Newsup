"""Reddit JSON fetcher for grassroots crisis signals (leaks, protests, inaction).

Uses the public `.json` endpoint (no OAuth needed) with a descriptive
User-Agent, which is what avoids the anonymous-client HTTP 429 Reddit applies
to the default python-requests UA. Subreddits are fetched concurrently via
aiohttp rather than sequentially.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

import aiohttp

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

REDDIT_HOT_URL = "https://www.reddit.com/r/{subreddit}/hot.json?limit=50"
USER_AGENT = "newsup-accountability-bot/1.0 (by u/newsup_pipeline)"

DEFAULT_SUBREDDITS = ["JEENEETards", "IndianAcademia"]

KEYWORDS = ["suicide", "leak", "scam", "nta", "protest"]

_TIMEOUT = aiohttp.ClientTimeout(total=15)


async def _fetch_one(session: aiohttp.ClientSession, subreddit: str) -> list[RawContentItem]:
    url = REDDIT_HOT_URL.format(subreddit=subreddit)
    headers = {"User-Agent": USER_AGENT}

    try:
        async with session.get(url, headers=headers, timeout=_TIMEOUT) as response:
            response.raise_for_status()
            # Reddit sometimes serves a charset-qualified content-type that
            # aiohttp's strict json() rejects; content_type=None disables the check.
            payload = await response.json(content_type=None)
    except aiohttp.ClientError as exc:
        logger.warning("Reddit fetch failed for r/%s: %s", subreddit, exc)
        return []

    posts = payload.get("data", {}).get("children", [])

    items: list[RawContentItem] = []
    for post in posts:
        data = post.get("data", {})
        title = data.get("title", "")
        selftext = data.get("selftext", "")
        haystack = f"{title} {selftext}".lower()

        if not any(keyword in haystack for keyword in KEYWORDS):
            continue

        created_utc = data.get("created_utc")
        published_at = (
            datetime.fromtimestamp(created_utc, tz=timezone.utc) if created_utc else None
        )

        permalink = data.get("permalink", "")
        items.append(
            RawContentItem(
                source="reddit",
                origin=f"r/{subreddit}",
                title=title,
                text=selftext or title,
                url=f"https://www.reddit.com{permalink}" if permalink else data.get("url", ""),
                published_at=published_at,
            )
        )
    return items


async def fetch_all_reddit_crises(subreddits: list[str] | None = None) -> list[RawContentItem]:
    """Fetch crisis-relevant posts across all target subreddits, concurrently."""
    subreddits = subreddits or DEFAULT_SUBREDDITS
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, sr) for sr in subreddits))
    return [item for batch in results for item in batch]
