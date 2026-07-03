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

    # Backend-only, used for dedup — see supabase_client.crisis_report_exists.
    source_url: str = ""


# ---------------------------------------------------------------------------
# Internal transport model — raw scraped content before AI processing
# ---------------------------------------------------------------------------


class RawContentItem(BaseModel):
    source: str  # "google_news" | "reddit" | "twitter"
    origin: str  # human-readable origin, e.g. search query, subreddit, handle
    title: str
    text: str
    url: str
    published_at: Optional[datetime] = None
