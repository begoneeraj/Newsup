"""Pydantic schemas mirroring lib/src/models/fact_check.dart and
lib/src/models/crisis_report.dart. Field names use snake_case (Supabase/Postgres
convention); enum values are UPPER_SNAKE_CASE string labels.

`source_url` on both schemas is a backend-only field (not present on the Dart
classes) used purely for deduplication in Supabase — the frontend can ignore it.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class FactCheckStatus(str, Enum):
    VERIFIED = "VERIFIED"
    FALSE = "FALSE"
    MISLEADING = "MISLEADING"
    PARTLY_TRUE = "PARTLY_TRUE"
    OUT_OF_CONTEXT = "OUT_OF_CONTEXT"
    SATIRE = "SATIRE"
    UNVERIFIED = "UNVERIFIED"


class SourceReliability(str, Enum):
    HIGH = "HIGH"
    MED = "MED"
    LOW = "LOW"


class CrisisStatus(str, Enum):
    UNRESOLVED = "UNRESOLVED"
    PARTIALLY_RESOLVED = "PARTIALLY_RESOLVED"
    RESOLVED = "RESOLVED"


class EvidenceType(str, Enum):
    PDF = "PDF"
    LIVE = "LIVE"
    DOCUMENT = "DOCUMENT"


# ---------------------------------------------------------------------------
# Fact Check — mirrors lib/src/models/fact_check.dart
# ---------------------------------------------------------------------------


class SourceRef(BaseModel):
    title: str
    url: str
    published_at: datetime


class FactCheckSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    claim_text: str
    origin: str
    status: FactCheckStatus
    evidence_confidence: int = Field(ge=0, le=100)
    source_reliability: SourceReliability
    independent_confirmations: int = 0
    official_confirmation: bool = False
    sources: list[SourceRef] = Field(default_factory=list)
    expert_analysis: Optional[str] = None
    genz_summary: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    # Backend-only, used for dedup — see supabase_client.fact_check_exists.
    source_url: str = ""

    # Backend-only, 384-dim sentence embedding for semantic dedup — see
    # ai_processor.embeddings and supabase_client.find_similar_fact_check.
    embedding: Optional[list[float]] = None

    # Backend-only, fast exact-match dedup pre-filter — see
    # utils.headline_hash and supabase_client.find_by_headline_hash.
    headline_hash: Optional[str] = None


# ---------------------------------------------------------------------------
# Crisis Report — mirrors lib/src/models/crisis_report.dart
# ---------------------------------------------------------------------------


class TimelineEvent(BaseModel):
    date: datetime
    title: str
    description: str
    # Hex color for the Dart-side `Color`. The AI model isn't asked to choose one;
    # the pipeline stamps a default and product can refine it later.
    status_color: str = "#EF4444"


class EvidenceItem(BaseModel):
    title: str
    url: str
    type: EvidenceType = EvidenceType.DOCUMENT


class CrisisReportSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    title: str
    status: CrisisStatus = CrisisStatus.UNRESOLVED
    event_start_date: datetime
    remedial_actions_count: int = 0
    rti_filings_total: int = 0
    rti_filings_answered: int = 0
    timeline_events: list[TimelineEvent] = Field(default_factory=list)
    evidence_items: list[EvidenceItem] = Field(default_factory=list)

    # The specific word/phrase in the source text Groq judged as the signal
    # that escalated this item to crisis classification (MODEL_COMPLEX) —
    # a transparency detail shown on the crisis card. None if the model
    # didn't identify one.
    trigger_keyword: Optional[str] = None

    # Backend-only, used for dedup — see supabase_client.crisis_report_exists.
    source_url: str = ""

    # Backend-only, 384-dim sentence embedding for semantic dedup — see
    # ai_processor.embeddings and supabase_client.find_similar_crisis_report.
    embedding: Optional[list[float]] = None

    # Backend-only, fast exact-match dedup pre-filter — see
    # utils.headline_hash and supabase_client.find_by_headline_hash.
    headline_hash: Optional[str] = None


# ---------------------------------------------------------------------------
# Crisis Event — quick type/severity/tag classification (`crises` table, see
# supabase/migrations/0008_crisis_events_and_statistics.sql). Distinct from
# CrisisReportSchema above (`crisis_reports`, RTI-filing/timeline tracking of
# an ongoing institutional crisis) — this is a lighter-weight classification
# used to tag any crisis-adjacent headline. See
# groq_processor._CRISIS_CLASSIFIER_SYSTEM_PROMPT.
# ---------------------------------------------------------------------------


class CrisisEventType(str, Enum):
    EXAM_LEAK = "exam_leak"
    STUDENT_SUICIDE = "student_suicide"
    GENDER_VIOLENCE = "gender_violence"
    WEATHER_DISASTER = "weather_disaster"
    EARTHQUAKE = "earthquake"
    AI_TECH = "ai_tech"
    EXAM_DELAY = "exam_delay"
    OTHER_CRISIS = "other_crisis"


class CrisisEventSeverity(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class CrisisEventStatus(str, Enum):
    ONGOING = "ongoing"
    RESOLVED = "resolved"
    DEVELOPING = "developing"


class CrisisEventSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    type: CrisisEventType
    title: str
    severity: CrisisEventSeverity
    status: CrisisEventStatus
    trigger_keyword: Optional[str] = None
    tags: list[str] = Field(default_factory=list)
    description: str
    affects_students: bool = False

    # Backend-only: the raw headline that triggered this classification,
    # stamped by main.py after validation (not part of the model's own output).
    source_headline: str = ""

    # Backend-only, fast exact-match dedup pre-filter — see
    # supabase/migrations/0010_crises_headline_hash.sql and
    # supabase_client.find_by_headline_hash. Without this, the same story
    # reported by multiple outlets minted one `crises` row per outlet.
    headline_hash: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Statistic — extracted quantitative data point (`statistics` table, see
# supabase/migrations/0008_crisis_events_and_statistics.sql). See
# groq_processor._STATS_EXTRACTOR_SYSTEM_PROMPT.
# ---------------------------------------------------------------------------


class StatCategory(str, Enum):
    STUDENT_WELFARE = "student_welfare"
    GENDER_VIOLENCE = "gender_violence"
    DISASTER = "disaster"
    EDUCATION = "education"
    AI_ADOPTION = "ai_adoption"


class StatisticSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    metric: str
    value: float
    year: Optional[int] = None
    source: str
    category: StatCategory
    created_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Public Event — generalized, dual-written aggregation layer over
# fact_checks / crisis_reports / crises (see
# supabase/migrations/0009_public_events.sql and src/pipeline/public_events.py).
# Does NOT replace those tables. event_type is a deliberately trimmed subset
# of a much larger eventual vocabulary — extend it (and the migration's check
# constraint) only when a phase actually produces a new type.
# ---------------------------------------------------------------------------


class PublicEventType(str, Enum):
    EXAM_LEAK = "exam_leak"
    STUDENT_SUICIDE = "student_suicide"
    GENDER_VIOLENCE = "gender_violence"
    WEATHER_DISASTER = "weather_disaster"
    EARTHQUAKE = "earthquake"
    AI_TECH = "ai_tech"
    EXAM_DELAY = "exam_delay"
    OTHER_CRISIS = "other_crisis"
    COURT_CASE = "court_case"
    GOVERNMENT_POLICY = "government_policy"
    ECONOMY = "economy"
    CRIME = "crime"
    TECHNOLOGY = "technology"
    MISC = "misc"


class PublicEventSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    title: str
    summary: str
    event_type: PublicEventType
    category: Optional[str] = None
    subcategory: Optional[str] = None

    # Computed deterministically by pipeline.public_events.compute_importance_score
    # — never AI-guessed. See that function's docstring.
    importance_score: Optional[int] = Field(default=None, ge=0, le=100)
    severity: Optional[CrisisEventSeverity] = None
    status: Optional[CrisisEventStatus] = None

    country: str = "India"
    state: Optional[str] = None
    district: Optional[str] = None
    city: Optional[str] = None

    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    last_updated: datetime = Field(default_factory=datetime.utcnow)

    confidence: Optional[float] = Field(default=None, ge=0, le=1)

    official_sources: list[dict] = Field(default_factory=list)
    media_sources: list[dict] = Field(default_factory=list)
    reddit_sources: list[dict] = Field(default_factory=list)
    youtube_sources: list[dict] = Field(default_factory=list)

    timeline: list[TimelineEvent] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    keywords: list[str] = Field(default_factory=list)

    embedding: Optional[list[float]] = None
    related_events: list[uuid.UUID] = Field(default_factory=list)

    image_url: Optional[str] = None
    notification_sent: bool = False
    verified: bool = False

    # Provenance / idempotent dual-write key — see
    # supabase_client.insert_public_event.
    source_table: str  # "fact_checks" | "crisis_reports" | "crises"
    source_id: uuid.UUID
    headline_hash: Optional[str] = None
    source_url: str = ""

    created_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Internal transport model — raw scraped content before AI processing
# ---------------------------------------------------------------------------


class RawContentItem(BaseModel):
    source: str  # "google_news" | "reddit" | "twitter" | "youtube"
    origin: str  # human-readable origin, e.g. search query, subreddit, handle
    title: str
    text: str
    url: str

    # Durable evidence URL (e.g. a Supabase Storage copy of a Reddit-hosted
    # image), preferred over `url` when building an EvidenceItem so the
    # evidence survives even if the original post/page is deleted.
    evidence_url: Optional[str] = None
    published_at: Optional[datetime] = None

    # The publishing outlet, when the fetcher can identify one distinct from
    # `origin` (e.g. Google News' <source> tag gives the actual publisher,
    # not the search query). Falls back to `origin` in main.py when unset.
    outlet_name: Optional[str] = None


# ---------------------------------------------------------------------------
# Source tracking / coverage / fact_checks_v2 — see
# supabase/migrations/0006_source_tracking_and_fact_checks_v2.sql. These
# extend a fact_checks (or crisis_reports) row rather than a standalone
# "news item"; outlet_credibility_score is always looked up from the curated
# outlet_credibility table (src/database/outlet_credibility.py), never
# generated by the AI pipeline.
# ---------------------------------------------------------------------------


class OutletSourceSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    fact_check_id: Optional[uuid.UUID] = None
    crisis_report_id: Optional[uuid.UUID] = None
    outlet_name: str
    outlet_url: str
    publish_time: Optional[datetime] = None
    # From outlet_credibility only; None if the outlet has no curated score.
    outlet_credibility_score: Optional[float] = None


class Consensus(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class CoverageAnalysisSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    fact_check_id: Optional[uuid.UUID] = None
    crisis_report_id: Optional[uuid.UUID] = None
    total_outlets: int = 0
    outlets_list: list[str] = Field(default_factory=list)
    consensus: Consensus
    created_at: datetime = Field(default_factory=datetime.utcnow)


class FactCheckV2Status(str, Enum):
    VERIFIED = "VERIFIED"
    DISPUTED = "DISPUTED"
    NEEDS_MORE_INFO = "NEEDS_MORE_INFO"


class EvidenceItemV2(BaseModel):
    source: str
    url: Optional[str] = None
    extracted_quote: str
    relevance_score: float = Field(ge=0, le=1)


class Perspective(BaseModel):
    sources: list[str] = Field(default_factory=list)
    summary: str


class Perspectives(BaseModel):
    pro: Perspective
    against: Perspective


class FactCheckV2Schema(BaseModel):
    """Claim-level, legally-safe fact-check layer. Never accuses an outlet —
    only cites official sources (PIB, ministries, courts, govt releases) as
    evidence. See groq_processor._FACT_CHECK_V2_SYSTEM_PROMPT."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    fact_check_id: uuid.UUID
    claim: str
    status: FactCheckV2Status
    evidence: list[EvidenceItemV2] = Field(default_factory=list)
    verdict: str
    confidence: float = Field(ge=0, le=1)
    perspectives: Optional[Perspectives] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
