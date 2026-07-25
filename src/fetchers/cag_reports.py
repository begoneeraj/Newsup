"""Fetcher for reports from the Comptroller and Auditor General of India (CAG).

The CAG website doesn't have a structured API. This fetcher simulates one by
scraping the recent reports page. It's a "niche" source for the
Underreported Topics module, providing high-signal information about
government finances and performance that often receives little mainstream
media attention.
"""

from __future__ import annotations

import logging
import re
import urllib.request

from bs4 import BeautifulSoup

from utils.keyword_match import keyword_matches

logger = logging.getLogger(__name__)

_CAG_REPORTS_URL = "https://cag.gov.in/en/reports-list"
_USER_AGENT = "newsup-bot/1.0"


def fetch_cag_reports_for_topic(keywords: list[str]) -> list[dict]:
    """Fetches recent CAG reports and filters them by keywords."""
    items = []
    try:
        req = urllib.request.Request(_CAG_REPORTS_URL, headers={"User-Agent": _USER_AGENT})
        with urllib.request.urlopen(req, timeout=30) as resp:
            soup = BeautifulSoup(resp.read(), "html.parser")

        for row in soup.select("table.datatable-reports tbody tr"):
            cells = row.find_all("td")
            if len(cells) < 3:
                continue

            title_cell = cells[1]
            title = title_cell.get_text(strip=True)
            link_tag = title_cell.find("a")
            url = link_tag["href"] if link_tag else ""

            if keyword_matches(keywords, title.lower()):
                items.append({"title": title, "url": url, "state": None})
    except Exception:
        logger.exception("Failed to fetch or parse CAG reports page.")
    return items