"""Reddit JSON fetcher for grassroots crisis signals (leaks, protests, inaction).

Uses the public `.json` endpoint (no OAuth needed) with a descriptive
User-Agent, which is what avoids the anonymous-client HTTP 429 Reddit applies
to the default python-requests UA. Subreddits are fetched concurrently via
aiohttp rather than sequentially.

Posts linking a directly-hosted image are re-uploaded to Supabase Storage
(evidence_vault bucket) so the evidence survives even if Reddit later removes
the post or image.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

import aiohttp

from database.supabase_client import upload_to_supabase_storage
from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

# /new.json, not /hot.json: hot-ranked posts barely change run to run (score-
# sorted, not time-sorted), so a 4-hourly cron polling /hot.json mostly
# re-fetches the same top posts and never surfaces genuinely new ones until
# they've already accumulated enough score to break into "hot". /new.json is
# time-sorted, so each run actually sees what's new since last time.
REDDIT_NEW_URL = "https://www.reddit.com/r/{subreddit}/new.json?limit=50"
USER_AGENT = "newsup-accountability-bot/1.0 (by u/newsup_pipeline)"

DEFAULT_SUBREDDITS = ["JEENEETards", "IndianAcademia"]

KEYWORDS = ["suicide", "leak", "scam", "nta", "protest"]

_TIMEOUT = aiohttp.ClientTimeout(total=15)
_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".gif", ".webp")


def _looks_like_image(url: str) -> bool:
    return url.lower().split("?")[0].endswith(_IMAGE_EXTENSIONS)


async def _preserve_image_evidence(
    session: aiohttp.ClientSession, image_url: str, post_id: str
) -> Optional[str]:
    """Download a Reddit-hosted image and re-host it in Supabase Storage.

    Returns the new public Supabase URL, or None if the download/upload fails
    (in which case the caller falls back to the original Reddit URL).
    """
    try:
        async with session.get(image_url, timeout=_TIMEOUT) as response:
            response.raise_for_status()
            content_type = response.headers.get("Content-Type", "image/jpeg")
            image_bytes = await response.read()
    except aiohttp.ClientError as exc:
        logger.warning("Failed to download Reddit image %s: %s", image_url, exc)
        return None

    extension = content_type.split("/")[-1].split(";")[0] or "jpg"
    filename = f"reddit/{post_id}.{extension}"

    try:
        # supabase-py's storage upload is synchronous; run it off the event
        # loop so it doesn't stall other concurrent fetches.
        return await asyncio.to_thread(upload_to_supabase_storage, image_bytes, filename, content_type)
    except Exception:
        logger.exception("Failed to upload evidence image for post %s", post_id)
        return None


async def _fetch_one(session: aiohttp.ClientSession, subreddit: str) -> list[RawContentItem]:
    url = REDDIT_NEW_URL.format(subreddit=subreddit)
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
        post_url = f"https://www.reddit.com{permalink}" if permalink else data.get("url", "")

        evidence_url = None
        image_url = data.get("url_overridden_by_dest")
        if image_url and _looks_like_image(image_url):
            evidence_url = await _preserve_image_evidence(session, image_url, data.get("id", ""))

        items.append(
            RawContentItem(
                source="reddit",
                origin=f"r/{subreddit}",
                title=title,
                text=selftext or title,
                url=post_url,
                published_at=published_at,
                evidence_url=evidence_url,
            )
        )
    return items


async def fetch_all_reddit_crises(subreddits: list[str] | None = None) -> list[RawContentItem]:
    """Fetch crisis-relevant posts across all target subreddits, concurrently."""
    subreddits = subreddits or DEFAULT_SUBREDDITS
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, sr) for sr in subreddits))
    return [item for batch in results for item in batch]
