"""Mediastack fetcher — https://mediastack.com/ (apilayer).

Plan features must be verified against the account dashboard. This client
always uses HTTPS and never downgrades to HTTP to accommodate a plan: doing
so would transmit the API key in cleartext.

Quota handling:
- The free tier's quota is monthly (100 calls/month at review), not
  daily. rate_limiter.py only models a rolling daily window, so this fetcher
  tracks a conservative self-imposed daily slice (MEDIASTACK_MONTHLY_LIMIT /
  31) rather than the true monthly window — it under-uses the quota by a
  small margin instead of risking exhausting a month's calls in a few days.
"""

from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime, timezone

import aiohttp

from database.rate_limiter import can_fetch, record_request
from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

MEDIASTACK_URL = "https://api.mediastack.com/v1/news"
SOURCE_NAME = "mediastack"
MEDIASTACK_MONTHLY_LIMIT = int(os.environ.get("MEDIASTACK_MONTHLY_LIMIT", "100"))
DAILY_LIMIT = max(0, MEDIASTACK_MONTHLY_LIMIT // 31)

_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _parse_published_at(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


async def fetch_all_mediastack(country_code: str = "in") -> list[RawContentItem]:
    api_key = os.environ.get("MEDIASTACK_API_KEY")
    if not api_key:
        logger.warning("MEDIASTACK_API_KEY not set; skipping Mediastack fetch")
        return []

    if not can_fetch(SOURCE_NAME, DAILY_LIMIT):
        logger.warning("Mediastack daily quota slice exhausted; skipping this run")
        return []

    items: list[RawContentItem] = []
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(
                MEDIASTACK_URL,
                params={"access_key": api_key, "countries": country_code, "languages": "en"},
                timeout=_TIMEOUT,
            ) as response:
                record_request(SOURCE_NAME, DAILY_LIMIT)
                payload = await response.json()
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            logger.warning("Mediastack fetch failed (%s); request details omitted to protect the API key", type(exc).__name__)
            return []

    if "error" in payload:
        logger.warning("Mediastack returned an API error; response details omitted to protect credentials")
        return []

    for article in payload.get("data") or []:
        items.append(
            RawContentItem(
                source="mediastack",
                origin=f"mediastack:{country_code}",
                title=(article.get("title") or "").strip(),
                text=(article.get("description") or "").strip(),
                url=article.get("url", ""),
                published_at=_parse_published_at(article.get("published_at")),
                outlet_name=article.get("source"),
            )
        )

    logger.info("Mediastack: fetched %d articles", len(items))
    return items
