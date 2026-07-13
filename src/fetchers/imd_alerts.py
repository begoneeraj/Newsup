"""IMD (India Meteorological Department) weather alert feed — public RSS,
no API key. The other "gov_alerts" source alongside
src/fetchers/usgs_earthquakes.py; official structured data, so
main.py::process_gov_alert skips the Groq classification pass for these
items.

NOTE: IMD's public RSS endpoint has moved before and isn't guaranteed to
stay at the URL below — verify it's live before relying on this in
production (curl it, or check https://mausam.imd.gov.in for the current
"RSS Feeds" link) and update IMD_RSS_URL / set the IMD_RSS_URL env var if
it's changed. Fetch failures are caught and logged rather than raised, same
as every other fetcher in this package, so a stale/broken URL degrades to
"no IMD alerts this run" instead of failing the whole cron job.
"""

from __future__ import annotations

import logging
import os
import re
from datetime import datetime, timezone
from typing import Optional

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

IMD_RSS_URL = os.environ.get(
    "IMD_RSS_URL", "https://mausam.imd.gov.in/backend/assets/rss/rss_state.xml"
)

_TAG_RE = re.compile(r"<[^>]+>")
_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _strip_html(raw: str) -> str:
    return _TAG_RE.sub(" ", raw).strip()


def _parse_entry(entry) -> Optional[RawContentItem]:
    title = entry.get("title", "").strip()
    if not title:
        return None

    published_at = None
    if getattr(entry, "published_parsed", None):
        published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

    return RawContentItem(
        source="imd",
        origin="IMD",
        title=title,
        text=_strip_html(entry.get("summary", "")) or title,
        url=entry.get("link", ""),
        published_at=published_at,
        outlet_name="IMD",
    )


async def fetch_all_imd_alerts() -> list[RawContentItem]:
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(IMD_RSS_URL, timeout=_TIMEOUT) as response:
                raw_bytes = await response.read()
    except aiohttp.ClientError as exc:
        logger.warning("IMD alert fetch failed: %s", exc)
        return []

    feed = feedparser.parse(raw_bytes)
    if feed.bozo and not feed.entries:
        logger.warning("IMD alert feed failed to parse: %s", getattr(feed, "bozo_exception", "unknown error"))
        return []

    items = [_parse_entry(entry) for entry in feed.entries]
    return [item for item in items if item is not None]
