"""YouTube transcript fetcher — for official statements from ministry/NTA
press briefings, parliamentary hearings, and news debates uploaded to YouTube.

There's no automated video-discovery step here (that would need the YouTube
Data API and its own quota); DEFAULT_VIDEO_IDS is a curated list operators
populate by hand. Transcripts can run to thousands of words, so each one is
condensed via Groq before becoming a RawContentItem's `text`, keeping later
schema-extraction calls well within context-window budgets.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

from groq import Groq
from youtube_transcript_api import TranscriptsDisabled, YouTubeTranscriptApi, YouTubeTranscriptApiException

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

# Overridable via env var; mirrors ai_processor.groq_processor's fast model.
SUMMARY_MODEL = os.environ.get("GROQ_MODEL_FAST", "llama-3.1-8b-instant")

# No real video IDs are known ahead of time — populate this with official
# press-briefing / hearing / debate video IDs as they're identified.
DEFAULT_VIDEO_IDS: list[str] = []

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
    video_ids = video_ids if video_ids is not None else DEFAULT_VIDEO_IDS
    if not video_ids:
        return []

    results = await asyncio.gather(*(asyncio.to_thread(_fetch_one_sync, vid) for vid in video_ids))
    return [item for item in results if item is not None]
