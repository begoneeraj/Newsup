"""Reddit JSON fetcher for grassroots crisis signals (leaks, protests, inaction).

Uses the public `.json` endpoint (no OAuth needed) with a descriptive
User-Agent, which is what avoids the anonymous-client HTTP 429 Reddit applies
to the default python-requests UA.
"""

from __future__ import annotations

import logging
import time
from datetime import datetime, timezone

import requests

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

REDDIT_HOT_URL = "https://www.reddit.com/r/{subreddit}/hot.json?limit=50"
USER_AGENT = "newsup-accountability-bot/1.0 (by u/newsup_pipeline)"

DEFAULT_SUBREDDITS = ["JEENEETards", "IndianAcademia"]

KEYWORDS = ["suicide", "leak", "scam", "nta", "protest"]


def fetch_reddit_crises(subreddit: str) -> list[RawContentItem]:
    """Fetch hot posts from a subreddit, filtered to crisis-relevant keywords."""
    url = REDDIT_HOT_URL.format(subreddit=subreddit)
    headers = {"User-Agent": USER_AGENT}

    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
    except requests.RequestException as exc:
        logger.warning("Reddit fetch failed for r/%s: %s", subreddit, exc)
        return []

    payload = response.json()
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


def fetch_all_reddit_crises(subreddits: list[str] | None = None) -> list[RawContentItem]:
    """Fetch crisis-relevant posts across all target subreddits."""
    subreddits = subreddits or DEFAULT_SUBREDDITS
    results: list[RawContentItem] = []
    for subreddit in subreddits:
        results.extend(fetch_reddit_crises(subreddit))
        time.sleep(2)  # stay polite between sequential requests to the same host
    return results
