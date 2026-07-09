"""Builds public_events rows (Phase 2 of the Public Events roadmap — see
supabase/migrations/0009_public_events.sql). Dual-writes off the output the
main pipeline already produces for fact_checks / crisis_reports / crises;
never runs its own Groq call and never blocks the caller's existing insert
if something here fails (see try/except at each main.py call site).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from models.schemas import (
    CrisisEventSchema,
    CrisisReportSchema,
    FactCheckSchema,
    PublicEventSchema,
    PublicEventType,
    RawContentItem,
)

# Keyword -> PublicEventType rules, checked in order, first match wins.
# Deliberately simple substring matching — no AI call. Falls back to MISC.
# Superset of main.CRISIS_KEYWORDS plus a few general-purpose buckets that
# don't warrant their own crisis-classifier call.
_KEYWORD_TYPE_RULES: list[tuple[list[str], PublicEventType]] = [
    (["neet", "jee", "upsc", "paper leak"], PublicEventType.EXAM_LEAK),
    (["exam postponed", "exam delayed", "result delayed"], PublicEventType.EXAM_DELAY),
    (["student suicide", "kota student", "student death"], PublicEventType.STUDENT_SUICIDE),
    (["rape", "violence against women", "domestic abuse", "sexual assault"], PublicEventType.GENDER_VIOLENCE),
    (["flood", "cyclone", "drought", "landslide"], PublicEventType.WEATHER_DISASTER),
    (["earthquake", "seismic"], PublicEventType.EARTHQUAKE),
    (["chatgpt", "artificial intelligence", "ai regulation", " llm "], PublicEventType.AI_TECH),
    (["supreme court", "high court", "court order", "court hearing", "court verdict"], PublicEventType.COURT_CASE),
    (["ministry", "government scheme", "cabinet approves"], PublicEventType.GOVERNMENT_POLICY),
    (["gdp", "inflation", "rbi", "sensex"], PublicEventType.ECONOMY),
    (["murder", "theft", "election fraud", "financial fraud"], PublicEventType.CRIME),
    (["startup funding", "app launch", "chip manufacturing"], PublicEventType.TECHNOLOGY),
]

# item.source -> which *_sources bucket it counts as. See src/fetchers/*.py
# for the exact source strings each fetcher tags items with.
_MEDIA_SOURCE_TAGS = {"google_news", "newsdata", "mediastack", "rss_outlet", "reddit_news", "twitter"}
_REDDIT_SOURCE_TAGS = {"reddit"}
_YOUTUBE_SOURCE_TAGS = {"youtube"}

# A handful of major Indian states/cities for simple substring extraction —
# no geocoding API, no AI call. Extend this list over time; absence just
# leaves state/city null, never guessed.
_INDIAN_STATES = [
    "Maharashtra", "Uttar Pradesh", "Bihar", "West Bengal", "Madhya Pradesh",
    "Tamil Nadu", "Rajasthan", "Karnataka", "Gujarat", "Andhra Pradesh",
    "Odisha", "Telangana", "Kerala", "Jharkhand", "Assam", "Punjab",
    "Haryana", "Chhattisgarh", "Delhi", "Jammu and Kashmir", "Uttarakhand",
]
_INDIAN_CITIES = [
    "Mumbai", "Delhi", "Bengaluru", "Bangalore", "Hyderabad", "Chennai",
    "Kolkata", "Pune", "Ahmedabad", "Jaipur", "Lucknow", "Kota", "Patna",
    "Chandigarh", "Bhopal", "Guwahati",
]


def classify_event_type(title: str, text: str) -> PublicEventType:
    """Deterministic, no-AI-call classification used when no CrisisEventSchema
    was produced for this item this run (see build_public_event)."""
    haystack = f"{title} {text}".lower()
    for keywords, event_type in _KEYWORD_TYPE_RULES:
        if any(kw in haystack for kw in keywords):
            return event_type
    return PublicEventType.MISC


def _extract_place(text: str, candidates: list[str]) -> Optional[str]:
    for name in candidates:
        if name.lower() in text.lower():
            return name
    return None


def _bucket_sources(item: RawContentItem) -> dict[str, list[dict]]:
    entry = {
        "title": item.title,
        "url": item.url,
        "published_at": (item.published_at or datetime.now(timezone.utc)).isoformat(),
    }
    buckets = {"official_sources": [], "media_sources": [], "reddit_sources": [], "youtube_sources": []}
    if item.source in _REDDIT_SOURCE_TAGS:
        buckets["reddit_sources"].append(entry)
    elif item.source in _YOUTUBE_SOURCE_TAGS:
        buckets["youtube_sources"].append(entry)
    elif item.source in _MEDIA_SOURCE_TAGS:
        buckets["media_sources"].append(entry)
    return buckets


def build_public_event(
    item: RawContentItem,
    *,
    source_table: str,
    source_id: str,
    embedding: list[float],
    headline_hash: Optional[str],
    importance_score: Optional[int],
    fact_check: Optional[FactCheckSchema] = None,
    crisis_report: Optional[CrisisReportSchema] = None,
    crisis_event: Optional[CrisisEventSchema] = None,
) -> dict:
    """Build a public_events row dict, ready for insert_public_event.

    Exactly one of fact_check / crisis_report / crisis_event should be set,
    matching source_table ("fact_checks" / "crisis_reports" / "crises").
    """
    if crisis_event is not None:
        event_type = PublicEventType(crisis_event.type.value)
        title = crisis_event.title
        summary = crisis_event.description
        severity = crisis_event.severity
        status = crisis_event.status
        tags = crisis_event.tags
    elif fact_check is not None:
        event_type = classify_event_type(item.title, item.text)
        title = item.title
        summary = fact_check.genz_summary or fact_check.claim_text
        severity = None
        status = None
        tags = []
    elif crisis_report is not None:
        event_type = classify_event_type(item.title, item.text)
        title = crisis_report.title
        summary = item.title
        severity = None
        status = None
        tags = []
    else:
        raise ValueError("build_public_event requires one of fact_check/crisis_report/crisis_event")

    haystack = f"{item.title} {item.text}"
    schema = PublicEventSchema(
        title=title,
        summary=summary,
        event_type=event_type,
        importance_score=importance_score,
        severity=severity,
        status=status,
        state=_extract_place(haystack, _INDIAN_STATES),
        city=_extract_place(haystack, _INDIAN_CITIES),
        tags=tags,
        keywords=tags,
        embedding=embedding,
        source_table=source_table,
        source_id=uuid.UUID(str(source_id)),
        headline_hash=headline_hash,
        source_url=item.url,
        **_bucket_sources(item),
    )
    return schema.model_dump(mode="json")
