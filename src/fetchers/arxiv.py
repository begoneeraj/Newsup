"""arXiv preprint search — free public API, no key needed
(export.arxiv.org/api/query). Confirmed live via manual query before
writing this: returns a standard Atom feed feedparser parses the same way
it parses RSS (no bozo errors, same entry shape) — same async-fetch/
sync-parse split as rss_feeds.py.

Items from this fetcher route straight to the science_research module by
source (see main._PROMISE_EVIDENCE_SOURCES-style handling for "arxiv" —
unambiguous by source, no keyword matching needed, unlike Hindu Science RSS
which mixes research papers with general science journalism).
"""

from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timezone
from urllib.parse import quote_plus

import aiohttp
import feedparser

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

ARXIV_API_URL = (
    "https://export.arxiv.org/api/query?search_query={query}&max_results={max_results}"
    "&sortBy=submittedDate&sortOrder=descending"
)

# Topic keywords ORed together at the arXiv API query level (not
# post-filtered after fetch) so bandwidth/rate limit isn't spent pulling
# down papers outside these topics in the first place. Each term needs its
# own "all:" field prefix for the API to treat this as a proper boolean OR
# rather than a literal phrase search. Kept broad rather than over-
# constrained with category filters, since Groq's own india_relevance field
# (see ScienceResearchReportSchema) does the finer-grained relevance
# judgment downstream, same pattern ai_tech_reports.india_relevance already
# establishes for a different module.
_ARXIV_TOPICS = [
    "india", "climate", "health", "education", "AI", "semiconductor",
    "space", "medicine",
]
ARXIV_QUERY = " OR ".join(f"all:{topic}" for topic in _ARXIV_TOPICS)

DEFAULT_QUERIES = [ARXIV_QUERY]

_MAX_RESULTS_PER_QUERY = 10
_TAG_RE = re.compile(r"<[^>]+>")
_TIMEOUT = aiohttp.ClientTimeout(total=20)
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}


def _strip_html(raw: str) -> str:
    return _TAG_RE.sub(" ", raw).strip()


def _parse_feed(raw_bytes: bytes) -> list[RawContentItem]:
    feed = feedparser.parse(raw_bytes)
    if feed.bozo and not feed.entries:
        logger.warning("arXiv feed failed to parse: %s", feed.bozo_exception)
        return []

    items: list[RawContentItem] = []
    for entry in feed.entries:
        published_at = None
        if getattr(entry, "published_parsed", None):
            published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)

        items.append(
            RawContentItem(
                source="arxiv",
                origin="arXiv",
                title=entry.get("title", "").strip(),
                text=_strip_html(entry.get("summary", "")),
                url=entry.get("link", ""),
                published_at=published_at,
                outlet_name="arXiv",
            )
        )
    return items


async def _fetch_one(session: aiohttp.ClientSession, query: str) -> list[RawContentItem]:
    url = ARXIV_API_URL.format(query=quote_plus(query), max_results=_MAX_RESULTS_PER_QUERY)
    try:
        async with session.get(url, timeout=_TIMEOUT, headers=_HEADERS) as response:
            raw_bytes = await response.read()
    except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
        logger.warning("arXiv fetch failed for query=%r: %s", query, exc)
        return []
    return _parse_feed(raw_bytes)


async def fetch_all_arxiv(queries: list[str] | None = None) -> list[RawContentItem]:
    queries = queries or DEFAULT_QUERIES
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(*(_fetch_one(session, query) for query in queries))
    return [item for batch in results for item in batch]
