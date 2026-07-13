"""PRS Legislative Research (prsindia.org) bill tracker — independent,
non-official commentary on bill status used as promise_evidence for the
Government Promises Tracker (see pipeline.promise_evidence).

The RSS entry already listed for PRS in rss_feeds.py (prsindia.org/rss) is
dead (404 as of this writing) and was never actually delivering content, so
this scrapes the real server-rendered /billtrack listing + detail pages
directly (confirmed live via manual fetch before writing this — plain
Drupal HTML, not a JS SPA, so aiohttp + BeautifulSoup is enough; no browser
automation needed). Same async-fetch/sync-parse split as rss_feeds.py:
aiohttp does the network I/O, BeautifulSoup only parses already-downloaded
bytes.
"""

from __future__ import annotations

import asyncio
import logging
import re

import aiohttp
from bs4 import BeautifulSoup

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

_BASE_URL = "https://prsindia.org"
_LISTING_URL = f"{_BASE_URL}/billtrack"
_TIMEOUT = aiohttp.ClientTimeout(total=20)
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}

# Cap per run — this is an independent-evidence source polled every ~4h
# alongside the main news cron, not a bulk one-time import; no need to
# re-fetch every bill in the tracker every run.
_MAX_BILLS_PER_RUN = 15

_BILL_LINK_RE = re.compile(r"^/billtrack/(?!category/)[a-z0-9-]+$")


def _extract_bill_links(listing_html: str) -> list[str]:
    soup = BeautifulSoup(listing_html, "lxml")
    seen: dict[str, None] = {}
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if _BILL_LINK_RE.match(href):
            seen.setdefault(href, None)
    return [f"{_BASE_URL}{href}" for href in seen]


def _parse_bill_detail(url: str, detail_html: str) -> RawContentItem | None:
    soup = BeautifulSoup(detail_html, "lxml")

    title_tag = soup.find("h1") or soup.find(class_="field-name-title-field")
    title = title_tag.get_text(strip=True) if title_tag else None
    if not title:
        return None

    status_tag = soup.find(class_="field-name-field-own-status-title")
    status = status_tag.get_text(strip=True) if status_tag else ""

    ministry = None
    ministry_label = soup.find(string=re.compile(r"Ministry\s*:"))
    if ministry_label is not None:
        parent = ministry_label.find_parent("div")
        sibling = parent.find_next_sibling("div") if parent else None
        if sibling is not None:
            ministry = sibling.get_text(strip=True)

    # Best-effort summary: first few substantial paragraphs of the main
    # content area. Drupal wraps the body in a "content" region but the
    # exact wrapper class varies by page template, so fall back to just
    # the longest paragraphs on the page rather than a single fixed selector.
    paragraphs = [p.get_text(strip=True) for p in soup.find_all("p")]
    paragraphs = [p for p in paragraphs if len(p) > 40]
    summary = " ".join(paragraphs[:3])[:1500]

    text_parts = [part for part in (status, f"Ministry: {ministry}" if ministry else None, summary) if part]
    return RawContentItem(
        source="prs_legislative",
        origin="PRS Legislative Research",
        title=title,
        text="\n".join(text_parts),
        url=url,
        outlet_name="PRS Legislative Research",
    )


async def _fetch_text(session: aiohttp.ClientSession, url: str) -> str | None:
    try:
        async with session.get(url, timeout=_TIMEOUT, headers=_HEADERS) as response:
            if response.status != 200:
                logger.warning("PRS fetch got HTTP %d for %s", response.status, url)
                return None
            return await response.text()
    except aiohttp.ClientError as exc:
        logger.warning("PRS fetch failed for %s: %s", url, exc)
        return None


async def fetch_all_prs_bills() -> list[RawContentItem]:
    """Fetches the PRS billtrack listing, then the detail page for up to
    _MAX_BILLS_PER_RUN bills linked from it."""
    async with aiohttp.ClientSession() as session:
        listing_html = await _fetch_text(session, _LISTING_URL)
        if listing_html is None:
            return []

        bill_urls = _extract_bill_links(listing_html)[:_MAX_BILLS_PER_RUN]
        if not bill_urls:
            logger.warning("PRS billtrack listing returned no bill links — page structure may have changed")
            return []

        detail_htmls = await asyncio.gather(*(_fetch_text(session, url) for url in bill_urls))

    items: list[RawContentItem] = []
    for url, html in zip(bill_urls, detail_htmls):
        if html is None:
            continue
        item = _parse_bill_detail(url, html)
        if item is not None:
            items.append(item)
    return items
