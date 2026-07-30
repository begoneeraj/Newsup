"""GDELT DOC 2.0 API client for the Underreported Topics module.

Unlike the TypeScript fetchGdeltArticles.ts Cloud Function (which pulls a
broad firehose of all India-related news into Firestore for crisis
classification), this is a targeted client used only to get a *count* of
articles matching a specific keyword query over the last 24h.

The GDELT DOC 2.0 API is documented at https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/
"""

from __future__ import annotations

import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

_API_ENDPOINT = "https://api.gdeltproject.org/api/v2/doc/doc"
_USER_AGENT = os.environ.get("USER_AGENT", "newsup-bot/1.0")

# GDELT's 429 response body states its limit explicitly: "Please limit
# requests to one every 5 seconds", but live testing showed even calls
# spaced exactly that far apart still got 429'd back-to-back (their limiter
# appears burstier/stricter in practice than their own error message, or
# tracks a rolling window rather than a fixed per-request gap). 5.5s is the
# steady-state spacing; _RATE_LIMIT_BACKOFF_SECONDS below is the extra
# recovery time given specifically on a 429 before a single retry.
_REQUEST_DELAY_SECONDS = 5.5
_RATE_LIMIT_BACKOFF_SECONDS = 15

# GDELT's DOC 2.0 API has no standalone `sourcelang` query-string parameter -
# confirmed live: passing sourcelang=eng/hin/tam as a separate param returned
# articles in unrelated languages (Nepali, Marathi, Indonesian, Korean...)
# unfiltered, while embedding `sourcelang:hindi` *inside* the `query` value
# itself correctly returned Hindi-only results. GDELT also expects the full
# English language name here (e.g. "hindi"), not an ISO code, hence this map
# from the ISO 639-1 codes callers use.
_GDELT_LANGUAGE_NAMES = {"en": "english", "hi": "hindi", "ta": "tamil"}


def count_articles(query: str, lang: str | None = None, _retried: bool = False) -> int:
    """Returns the number of articles matching `query` in the last 24 hours.

    `lang` can be an ISO 639-1 code (e.g. "hi" for Hindi, "ta" for Tamil) to
    scope the search to that language.
    """
    yesterday = datetime.now(timezone.utc) - timedelta(days=1)
    start_datetime = yesterday.strftime("%Y%m%d%H%M%S")

    full_query = query
    if lang:
        gdelt_language = _GDELT_LANGUAGE_NAMES.get(lang, lang)
        full_query = f"{query} sourcelang:{gdelt_language}"

    params = {
        "query": full_query,
        "mode": "artlist",
        "format": "json",
        "startdatetime": start_datetime,
        "sort": "datedesc",
        # GDELT's `maxrecords` is capped at 250. We don't need the articles
        # themselves, only the count, but there's no "count-only" mode.
        # The total number of articles is not directly returned, so we infer
        # it from the length of the returned list. This means our count is
        # capped at 250, which is a reasonable proxy for "high volume" vs
        # the low single-digit counts of niche sources.
        "maxrecords": 250,
    }

    url = f"{_API_ENDPOINT}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = json.load(resp)
            count = len(payload.get("articles", []))
            logger.info("GDELT query='%s' lang=%s -> %d articles", query, lang, count)
            time.sleep(_REQUEST_DELAY_SECONDS)
            return count
    except urllib.error.HTTPError as exc:
        if exc.code == 429 and not _retried:
            logger.warning(
                "GDELT rate-limited (429) for query='%s' lang=%s, backing off %ds and retrying once",
                query,
                lang,
                _RATE_LIMIT_BACKOFF_SECONDS,
            )
            time.sleep(_RATE_LIMIT_BACKOFF_SECONDS)
            return count_articles(query, lang, _retried=True)
        logger.exception("GDELT request failed for query='%s' lang=%s", query, lang)
        time.sleep(_REQUEST_DELAY_SECONDS)
        return 0
    except Exception:
        logger.exception("GDELT request failed for query='%s' lang=%s", query, lang)
        time.sleep(_REQUEST_DELAY_SECONDS)
        return 0