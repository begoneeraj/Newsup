"""CAG (Comptroller and Auditor General of India) audit reports
(cag.gov.in) -- niche/official source for the underreported-topics module
(pipeline.underreported_topics). Confirmed live via manual fetch before
writing this: /en/audit-report lists report titles + detail links
server-rendered in plain HTML (no JS SPA), and report detail pages link
real PDF chapters under /uploads/download_audit_report/ -- same
aiohttp + BeautifulSoup shape as fetchers.prs_legislative, no browser
automation needed.

Only the listing page is fetched -- it already carries each report's full
title in the anchor text, which is enough for topic-keyword matching and an
example-source link, without the cost of fetching every detail page too.
"""

from __future__ import annotations

import logging
import re

import aiohttp
from bs4 import BeautifulSoup

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

_BASE_URL = "https://cag.gov.in"
_LISTING_URL = f"{_BASE_URL}/en/audit-report"
_TIMEOUT = aiohttp.ClientTimeout(total=20)
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}

# One listing-page fetch returns ~25-30 report links -- capped here so a
# single run stays cheap; this is a daily signal source, not a bulk
# historical import.
_MAX_REPORTS_PER_RUN = 25

_DETAIL_LINK_RE = re.compile(r"^/en/audit-report/details/\d+$")


def _extract_report_links(listing_html: str) -> list[tuple[str, str]]:
    """Returns (url, title) pairs, de-duplicated by href, in listing order."""
    soup = BeautifulSoup(listing_html, "lxml")
    seen: dict[str, str] = {}
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if not _DETAIL_LINK_RE.match(href):
            continue
        title = a.get_text(strip=True)
        if title and href not in seen:
            seen[href] = title
    return [(f"{_BASE_URL}{href}", title) for href, title in seen.items()]


async def fetch_all_cag_reports() -> list[RawContentItem]:
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(_LISTING_URL, timeout=_TIMEOUT, headers=_HEADERS) as response:
                if response.status != 200:
                    logger.warning("CAG audit-report listing got HTTP %d", response.status)
                    return []
                listing_html = await response.text()
    except aiohttp.ClientError as exc:
        logger.warning("CAG audit-report listing fetch failed: %s", exc)
        return []

    reports = _extract_report_links(listing_html)[:_MAX_REPORTS_PER_RUN]
    if not reports:
        logger.warning("CAG audit-report listing returned no report links — page structure may have changed")
        return []

    return [
        RawContentItem(
            source="cag_audit",
            origin="CAG Audit Reports",
            title=title,
            text=title,
            url=url,
            outlet_name="Comptroller and Auditor General of India",
        )
        for url, title in reports
    ]
