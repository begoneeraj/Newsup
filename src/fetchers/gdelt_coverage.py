"""GDELT DOC 2.0 API article-count lookups, used only by
pipeline.underreported_topics as a mainstream-coverage signal -- a topic's
GDELT article count (optionally scoped to a source language) stands in for
"how much mainstream media has covered this", independent of the Google
News RSS count that module also collects.

Not a RawContentItem fetcher like fetchers/*.py -- this returns GDELT's raw
article list (for a count and example-source links), not content routed
through main.py's process_and_store pipeline.

GDELT_TIMESPAN mirrors functions/src/fetchGdeltArticles.ts's confirmed-live
finding: timespan=15MIN is rejected by the API (HTTP 200 with a plain-text
"Timespan is too short." body, not JSON) even though it returns 200 -- a
larger window is needed for a reliably-JSON response. Reused here rather
than re-verified, since that finding came from live testing against this
same API; this module also needs a wider window than that ingestion
function anyway (a weekly count is a more meaningful "how much mainstream
coverage" signal than a 60-minute one).
"""

from __future__ import annotations

import logging
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)

_DOC_API_URL = "https://api.gdeltproject.org/api/v2/doc/doc"
_TIMEOUT = aiohttp.ClientTimeout(total=20)
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}
GDELT_TIMESPAN = "7d"


async def gdelt_article_search(query: str, *, sourcelang: Optional[str] = None, maxrecords: int = 20) -> list[dict]:
    """Returns GDELT's raw `articles` list for `query` scoped to India
    (sourcecountry:IN), optionally further scoped to a source language
    (e.g. "hin", "tam"). Fails open (empty list) on any network error, bad
    status, or non-JSON body -- a topic with a GDELT hiccup should just show
    zero mainstream-count from this signal, not break the whole run, same
    fail-open convention every fetcher in this codebase follows.
    """
    full_query = f"{query} sourcecountry:IN"
    if sourcelang:
        full_query += f" sourcelang:{sourcelang}"

    params = {
        "query": full_query,
        "mode": "artlist",
        "format": "json",
        "timespan": GDELT_TIMESPAN,
        "maxrecords": str(maxrecords),
        "sort": "datedesc",
    }

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(_DOC_API_URL, params=params, timeout=_TIMEOUT, headers=_HEADERS) as response:
                if response.status != 200:
                    logger.warning("GDELT doc search got HTTP %d for query=%r", response.status, query)
                    return []
                content_type = response.headers.get("content-type", "")
                if "application/json" not in content_type:
                    # GDELT quirk: some rejected params return HTTP 200 with a
                    # plain-text error body instead of JSON -- see module docstring.
                    body = await response.text()
                    logger.warning("GDELT doc search returned non-JSON body for query=%r: %s", query, body[:200])
                    return []
                payload = await response.json(content_type=None)
    except aiohttp.ClientError as exc:
        logger.warning("GDELT doc search failed for query=%r: %s", query, exc)
        return []

    articles = payload.get("articles")
    return articles if isinstance(articles, list) else []
