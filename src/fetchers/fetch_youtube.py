"""YouTube transcript fetcher — for official statements from ministry/NTA
press briefings, parliamentary hearings, and news debates uploaded to YouTube.

Video discovery uses the YouTube Data API v3 `search` endpoint (needs
YOUTUBE_API_KEY) to find recent videos matching DEFAULT_SEARCH_QUERIES;
DEFAULT_VIDEO_IDS remains available as a manual override/supplement for
specific videos operators want to force through regardless of search
results. Transcripts can run to thousands of words, so each one is
condensed via Groq before becoming a RawContentItem's `text`, keeping later
schema-extraction calls well within context-window budgets.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

import aiohttp
from groq import Groq
from youtube_transcript_api import TranscriptsDisabled, YouTubeTranscriptApi, YouTubeTranscriptApiException

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

# Overridable via env var; mirrors ai_processor.groq_processor's fast model.
SUMMARY_MODEL = os.environ.get("GROQ_MODEL_FAST", "llama-3.1-8b-instant")

# Manual override/supplement — operators can still force specific video IDs
# through regardless of what search discovers.
DEFAULT_VIDEO_IDS: list[str] = []

DEFAULT_SEARCH_QUERIES = [
    "NEET leak",
    "NTA scam",
    "Education Minister student protest",
]

# search.list costs 100 quota units/call; capped low to stay well within the
# free 10,000/day quota across 4 staggered runs/day and multiple queries.
_MAX_VIDEOS_PER_QUERY = 3
_SEARCH_URL = "https://www.googleapis.com/youtube/v3/search"
_SEARCH_TIMEOUT = aiohttp.ClientTimeout(total=15)


async def _search_one_query(
    session: aiohttp.ClientSession, api_key: str, query: str
) -> list[str]:
    params = {
        "key": api_key,
        "q": query,
        "part": "id",
        "type": "video",
        "order": "date",
        "relevanceLanguage": "en",
        "regionCode": "IN",
        "maxResults": str(_MAX_VIDEOS_PER_QUERY),
    }
    try:
        async with session.get(_SEARCH_URL, params=params, timeout=_SEARCH_TIMEOUT) as response:
            if response.status != 200:
                logger.warning(
                    "YouTube search failed for query=%r: HTTP %s", query, response.status
                )
                return []
            data = await response.json()
    except aiohttp.ClientError as exc:
        logger.warning("YouTube search failed for query=%r: %s", query, exc)
        return []

    return [
        item["id"]["videoId"]
        for item in data.get("items", [])
        if item.get("id", {}).get("videoId")
    ]


async def discover_video_ids(
    queries: list[str] | None = None, api_key: str | None = None
) -> list[str]:
    """Search YouTube for recent videos matching the target queries.

    Returns an empty list (rather than raising) if no API key is configured,
    so callers can fall back to DEFAULT_VIDEO_IDS alone.
    """
    api_key = api_key or os.environ.get("YOUTUBE_API_KEY")
    if not api_key:
        return []

    queries = queries if queries is not None else DEFAULT_SEARCH_QUERIES
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(
            *(_search_one_query(session, api_key, q) for q in queries)
        )

    seen: set[str] = set()
    video_ids: list[str] = []
    for batch in results:
        for video_id in batch:
            if video_id not in seen:
                seen.add(video_id)
                video_ids.append(video_id)
    return video_ids

_SUMMARY_SYSTEM_PROMPT = (
    "You condense video transcripts for a student accountability news app. "
    "Summarize the transcript in 3-4 sentences, focusing on concrete claims, "
    "official statements, numbers, and dates. Drop filler and repetition. "
    "Output plain text only, no markdown."
)

_client: Optional[Groq] = None


def _get_client() -> Groq:
    global _client
    if _client is None:
        _client = Groq(api_key=os.environ["GROQ_API_KEY"])
    return _client


def _fetch_transcript_text(video_id: str) -> Optional[str]:
    try:
        transcript = YouTubeTranscriptApi().fetch(video_id, languages=["en"])
    except TranscriptsDisabled:
        logger.warning("Transcripts disabled for video %s", video_id)
        return None
    except YouTubeTranscriptApiException as exc:
        logger.warning("Failed to fetch transcript for video %s: %s", video_id, exc)
        return None

    return " ".join(snippet.text for snippet in transcript)


def _summarize_transcript(video_id: str, transcript_text: str) -> Optional[str]:
    # A few thousand characters is plenty of context for a 3-4 sentence summary.
    trimmed = transcript_text[:12000]
    try:
        response = _get_client().chat.completions.create(
            model=SUMMARY_MODEL,
            messages=[
                {"role": "system", "content": _SUMMARY_SYSTEM_PROMPT},
                {"role": "user", "content": trimmed},
            ],
            temperature=0.2,
            max_tokens=400,
        )
    except Exception:
        logger.exception("Groq summarization failed for video %s", video_id)
        return None
    return response.choices[0].message.content.strip()


def _fetch_one_sync(video_id: str) -> Optional[RawContentItem]:
    transcript_text = _fetch_transcript_text(video_id)
    if not transcript_text:
        return None

    summary = _summarize_transcript(video_id, transcript_text)
    if not summary:
        return None

    return RawContentItem(
        source="youtube",
        origin=f"youtube:{video_id}",
        title=f"YouTube video {video_id}",
        text=summary,
        url=f"https://www.youtube.com/watch?v={video_id}",
    )


async def fetch_all_youtube(video_ids: list[str] | None = None) -> list[RawContentItem]:
    """Fetch + summarize transcripts for all target video IDs, concurrently.

    Both the transcript fetch and the Groq summarization call are synchronous
    (no async SDK for either), so each video is offloaded to a worker thread
    to avoid blocking the event loop other fetchers share.
    """
    if video_ids is None:
        discovered = await discover_video_ids()
        video_ids = list(dict.fromkeys(discovered + DEFAULT_VIDEO_IDS))
    if not video_ids:
        return []

    results = await asyncio.gather(*(asyncio.to_thread(_fetch_one_sync, vid) for vid in video_ids))
    return [item for item in results if item is not None]
