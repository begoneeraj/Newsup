"""sansad.in eLibrary (elibrary.sansad.in) — a DSpace 7 repository of
parliamentary papers (bills, committee reports, replies, statistical
statements), searched via its documented public REST API
(/server/api/discover/search/objects).

This is NOT the live Parliament Q&A search UI (sansad.in/ls/questions/
questions-and-answers) — that page is a Next.js SPA whose results endpoint
requires a POST request this fetcher wasn't able to safely reverse-engineer
(only the dropdown-population GET endpoints under sansad.in/api_ls/question/
were confirmed; the actual question-search POST endpoint/body wasn't
found). elibrary.sansad.in is a real, confirmed-working, documented
alternative that still gives independent official parliamentary records,
just not scoped to "written answers to a specific numbered question" the
way the spec originally envisioned.

Because of that gap, items from here are tagged source="sansad_elibrary"
(not "parliament_qa") and pipeline.promise_evidence maps them to
promise_evidence.source_type="other" rather than "parliament_qa" — "other"
does NOT count toward the fully_implemented independence threshold in
pipeline.promise_reverification.INDEPENDENT_SOURCE_TYPES. Re-classify as
"parliament_qa" only once the fetcher is confirmed to return actual
question-and-answer records specifically (would need the real search API
found and this module's query scoped to that record type).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime
from typing import Optional
from urllib.parse import quote_plus

import aiohttp

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

_SEARCH_URL = "https://elibrary.sansad.in/server/api/discover/search/objects"
_TIMEOUT = aiohttp.ClientTimeout(total=20)
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}

# Static query terms, same level of sophistication as
# fetchers.google_news.DEFAULT_QUERIES — a natural follow-up once this
# fetcher is live is to instead query per-tracked-promise (using each
# govt_promises.project_name as the search term) for much better relevance,
# which needs main.py to thread tracked promise names in before calling
# this, a bigger change than fits the current fetch_all_news_sources() shape.
DEFAULT_QUERIES = [
    "scheme implementation report",
    "budget utilization ministry",
    "project completion status",
]

_RESULTS_PER_QUERY = 5


def _parse_object(obj: dict) -> Optional[RawContentItem]:
    item = obj.get("_embedded", {}).get("indexableObject")
    if item is None:
        return None

    metadata = item.get("metadata", {})

    def _first(field: str) -> Optional[str]:
        values = metadata.get(field)
        return values[0]["value"] if values else None

    title = _first("dc.title") or item.get("name")
    if not title:
        return None

    date_issued = _first("dc.date.issued")
    published_at = None
    if date_issued:
        try:
            published_at = datetime.fromisoformat(date_issued.replace("Z", "+00:00"))
        except ValueError:
            published_at = None

    handle = item.get("handle")
    url = f"https://elibrary.sansad.in/handle/{handle}" if handle else _first("dc.identifier.uri") or ""

    doc_type = _first("dc.type") or ""
    collection = _first("dc.collection") or ""
    text = f"Type: {doc_type}. Collection: {collection}." if (doc_type or collection) else ""

    return RawContentItem(
        source="sansad_elibrary",
        origin="sansad.in eLibrary",
        title=title,
        text=text,
        url=url,
        published_at=published_at,
        outlet_name="Sansad eLibrary",
    )


async def _search_one(session: aiohttp.ClientSession, query: str) -> list[RawContentItem]:
    url = f"{_SEARCH_URL}?query={quote_plus(query)}&size={_RESULTS_PER_QUERY}"
    try:
        async with session.get(url, timeout=_TIMEOUT, headers=_HEADERS) as response:
            if response.status != 200:
                logger.warning("sansad eLibrary search got HTTP %d for query=%r", response.status, query)
                return []
            payload = await response.json(content_type=None)
    except aiohttp.ClientError as exc:
        logger.warning("sansad eLibrary search failed for query=%r: %s", query, exc)
        return []

    objects = (
        payload.get("_embedded", {}).get("searchResult", {}).get("_embedded", {}).get("objects", [])
    )
    items = [_parse_object(obj) for obj in objects]
    return [item for item in items if item is not None]


async def fetch_all_elibrary_records(queries: list[str] | None = None) -> list[RawContentItem]:
    queries = queries or DEFAULT_QUERIES
    async with aiohttp.ClientSession() as session:
        results = [await _search_one(session, query) for query in queries]
    return [item for batch in results for item in batch]


def fetch_elibrary_records_for_topic(keywords: list[str]) -> list[dict]:
    """For pipeline.underreported_topics, called via asyncio.to_thread (so
    synchronous, unlike fetch_all_elibrary_records above). Unlike PRS's
    fixed listing scrape, this search API already takes a list of query
    strings directly (see the `queries` param above), so each keyword
    becomes its own targeted search query instead of a client-side filter
    over a fixed fetch. asyncio.run() is safe here because asyncio.to_thread
    runs this in its own worker thread with no event loop of its own yet.
    """
    records = asyncio.run(fetch_all_elibrary_records(queries=keywords))
    return [{"title": record.title, "url": record.url, "state": None} for record in records]
