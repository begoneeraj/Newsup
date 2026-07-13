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
    FLOOD = "flood"
    CYCLONE = "cyclone"
    HEATWAVE = "heatwave"
    WEATHER_ALERT = "weather_alert"
    SUICIDE_SPREE = "suicide_spree"


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
    FLOOD = "flood"
    CYCLONE = "cyclone"
    HEATWAVE = "heatwave"
    WEATHER_ALERT = "weather_alert"
    SUICIDE_SPREE = "suicide_spree"


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


# ---------------------------------------------------------------------------
# Confidence classification — response shape for POST /classify (api_server.py),
# consumed by the TypeScript crisisClassifier Cloud Function as the base score
# that applyToneHeuristic() then adjusts. See groq_processor.process_confidence_classification.
# ---------------------------------------------------------------------------


class ConfidenceClassificationSchema(BaseModel):
    confidence: int = Field(ge=0, le=100)
    label: str


# ---------------------------------------------------------------------------
# Expansion modules — student crisis / AI & tech / govt promises / court
# cases. See truthlens_expansion_prompt.md and
# groq_processor._STUDENT_CRISIS_SYSTEM_PROMPT /
# _AI_TECH_SYSTEM_PROMPT / _GOVT_PROMISE_SYSTEM_PROMPT /
# _COURT_CASE_SYSTEM_PROMPT. Routed via main.route_expansion_module().
#
# The source prompt's tables FK source_headline_id to a `news_headlines`
# table that doesn't exist in this project; adapted to headline_hash, this
# project's actual dedup convention (see utils.headline_hash), instead.
# ---------------------------------------------------------------------------


class StudentCrisisSeverity(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class StudentCrisisType(str, Enum):
    PAPER_LEAK = "paper_leak"
    SUICIDE = "suicide"
    PROTEST = "protest"
    COACHING_MISCONDUCT = "coaching_misconduct"
    UNIVERSITY_ACTION = "university_action"
    SCHOLARSHIP = "scholarship"
    MENTAL_HEALTH = "mental_health"
    OTHER = "other"


class StudentCrisisReportSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    exam_or_context: str
    crisis_type: StudentCrisisType
    severity: StudentCrisisSeverity
    affected_count: Optional[int] = None
    state: Optional[str] = None
    institution: Optional[str] = None
    government_response: Optional[str] = None
    student_demand: Optional[str] = None
    court_involvement: bool = False
    fact_check_flag: bool = False
    headline_plain: str
    headline_genz: Optional[str] = None
    key_facts: list[str] = Field(default_factory=list)
    missing_info: Optional[str] = None
    next_step_to_watch: str

    source_url: str = ""
    headline_hash: Optional[str] = None
    processed_at: datetime = Field(default_factory=datetime.utcnow)


class AiTechCategory(str, Enum):
    AI_MODEL = "ai_model"
    AI_POLICY = "ai_policy"
    SEMICONDUCTOR = "semiconductor"
    FUNDING = "funding"
    DEEPFAKE = "deepfake"
    INDIA_AI_MISSION = "india_ai_mission"
    ROBOTICS = "robotics"
    DATA_CENTRE = "data_centre"
    BIG_TECH = "big_tech"
    INCIDENT = "incident"
    OTHER = "other"


class AiTechClaimType(str, Enum):
    LAUNCH = "launch"
    REGULATION = "regulation"
    FUNDING = "funding"
    CONTROVERSY = "controversy"
    RESEARCH = "research"
    ACQUISITION = "acquisition"
    BAN = "ban"
    OTHER = "other"


class HypeCheck(str, Enum):
    OVERHYPED = "overhyped"
    NEUTRAL = "neutral"
    UNDERSTATED = "understated"


class TechnicalAccuracy(str, Enum):
    ACCURATE = "accurate"
    MINOR_ERRORS = "minor_errors"
    MISLEADING = "misleading"
    CANNOT_VERIFY = "cannot_verify"


class AiTechReportSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    tech_category: AiTechCategory
    india_relevance: bool = False
    india_angle: Optional[str] = None
    companies_involved: list[str] = Field(default_factory=list)
    countries_involved: list[str] = Field(default_factory=list)
    claim_type: AiTechClaimType
    hype_check: HypeCheck
    technical_accuracy: TechnicalAccuracy
    headline_plain: str
    headline_genz: Optional[str] = None
    key_facts: list[str] = Field(default_factory=list)
    what_this_means_for_india: str
    next_milestone: Optional[str] = None
    sources_to_verify: list[str] = Field(default_factory=list)

    source_url: str = ""
    headline_hash: Optional[str] = None
    processed_at: datetime = Field(default_factory=datetime.utcnow)


class GovtPromiseCategory(str, Enum):
    METRO = "metro"
    HIGHWAY = "highway"
    SMART_CITY = "smart_city"
    AI_MISSION = "ai_mission"
    SEMICONDUCTOR = "semiconductor"
    SOCIAL_SCHEME = "social_scheme"
    DEFENCE = "defence"
    BUDGET_ALLOCATION = "budget_allocation"
    ELECTION_PROMISE = "election_promise"
    OTHER = "other"


class StateOrNational(str, Enum):
    NATIONAL = "national"
    STATE = "state"


class GovtPromiseStatus(str, Enum):
    ANNOUNCED = "announced"
    STARTED = "started"
    ONGOING = "ongoing"
    DELAYED = "delayed"
    STALLED = "stalled"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class GovtPromiseSource(str, Enum):
    NEWS_ARTICLE = "news_article"
    ELECTION_MANIFESTO = "election_manifesto"
    BUDGET_DOCUMENT = "budget_document"
    OFFICIAL_STATEMENT = "official_statement"
    OTHER = "other"


class GovtPromiseImplementationQuality(str, Enum):
    """Orthogonal to GovtPromiseStatus: status tracks project lifecycle
    stage (started/ongoing/completed...), this tracks how thoroughly that
    status has been independently verified. A promise can be
    current_status=COMPLETED while implementation_quality is still
    ON_PAPER_ONLY if the only evidence is the government's own inauguration
    press release. See pipeline.promise_reverification._apply_business_rules
    for the code-level rule that FULLY_IMPLEMENTED requires at least one
    independent source, not just a Groq-prompted instruction."""

    NOT_STARTED = "not_started"
    ON_PAPER_ONLY = "on_paper_only"
    PARTIALLY_IMPLEMENTED = "partially_implemented"
    FULLY_IMPLEMENTED = "fully_implemented"
    POOR_QUALITY_IMPLEMENTATION = "poor_quality_implementation"


class VerificationConfidence(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class PromiseEvidenceSourceType(str, Enum):
    PARLIAMENT_QA = "parliament_qa"
    CAG_REPORT = "cag_report"
    PRS_LEGISLATIVE = "prs_legislative"
    NEWS_ARTICLE = "news_article"
    OFFICIAL_PIB = "official_pib"
    MYGOV_SCHEME_PAGE = "mygov_scheme_page"
    MANIFESTO_PDF = "manifesto_pdf"
    BUDGET_DOCUMENT = "budget_document"
    OTHER = "other"


class PromiseEvidenceStance(str, Enum):
    SUPPORTS_DONE = "supports_done"
    CONTRADICTS_DONE = "contradicts_done"
    NEUTRAL_UPDATE = "neutral_update"


class GovtPromiseSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    project_name: str
    project_slug: str
    category: GovtPromiseCategory
    announcing_body: str
    state_or_national: StateOrNational
    state: Optional[str] = None
    announced_date: Optional[str] = None
    promised_completion_date: Optional[str] = None
    revised_completion_date: Optional[str] = None
    current_status: GovtPromiseStatus
    budget_allocated_crore: Optional[float] = None
    budget_spent_crore: Optional[float] = None
    broken_promise_flag: bool = False
    broken_promise_detail: Optional[str] = None
    beneficiaries: Optional[str] = None
    headline_plain: str
    ai_summary: str
    genz_summary: Optional[str] = None
    key_facts: list[str] = Field(default_factory=list)
    next_milestone: Optional[str] = None
    verification_sources: list[str] = Field(default_factory=list)

    # Party is deliberately a free-text field, not an enum: India's party
    # landscape is open-ended (national/state/alliance), unlike category's
    # ~10 fixed values, and is null for most non-election_promise rows.
    party: Optional[str] = None
    election_year: Optional[int] = None
    promise_source: GovtPromiseSource = GovtPromiseSource.NEWS_ARTICLE
    implementation_quality: Optional[GovtPromiseImplementationQuality] = None
    verification_confidence: VerificationConfidence = VerificationConfidence.LOW
    official_claim: Optional[str] = None
    ground_reality: Optional[str] = None
    last_verified_at: Optional[datetime] = None

    source_url: str = ""
    headline_hash: Optional[str] = None
    last_updated: datetime = Field(default_factory=datetime.utcnow)


class PromiseEvidenceSchema(BaseModel):
    """Append-only evidence trail for a govt_promises row. excerpt_summary
    is always a Groq-generated paraphrase, never a verbatim scraped quote
    (respects source copyright, keeps rows short enough to batch many into
    one Stage D reverification prompt)."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    promise_id: uuid.UUID
    source_type: PromiseEvidenceSourceType
    source_url: str = ""
    stance: PromiseEvidenceStance
    excerpt_summary: str
    observed_at: datetime = Field(default_factory=datetime.utcnow)


class GovtPromiseReverificationSchema(BaseModel):
    """Patch-shaped output of Stage D re-verification (see
    groq_processor._GOVT_PROMISE_REVERIFICATION_SYSTEM_PROMPT). Unlike
    GovtPromiseSchema this never re-derives project_name/category/etc. -
    only the verification-facing fields plus current_status/
    broken_promise_flag, since new evidence can also move those."""

    implementation_quality: GovtPromiseImplementationQuality
    verification_confidence: VerificationConfidence
    official_claim: str
    ground_reality: str
    current_status: GovtPromiseStatus
    broken_promise_flag: bool = False
    broken_promise_detail: Optional[str] = None


class PromiseEvidenceStanceSchema(BaseModel):
    """Output of Stage B's per-article stance classification (see
    groq_processor._PROMISE_EVIDENCE_STANCE_SYSTEM_PROMPT /
    pipeline.promise_evidence). Runs once per article fuzzy-matched to a
    tracked promise, not once per promise - source_type is already known
    from which fetcher produced the article, so Groq only decides stance
    and paraphrases the excerpt."""

    stance: PromiseEvidenceStance
    excerpt_summary: str


class SlowCrisisNarrativeGroqSchema(BaseModel):
    """Groq-only output for Track 2 (see
    groq_processor._SLOW_CRISIS_NARRATIVE_SYSTEM_PROMPT /
    pipeline.slow_crisis_narrative) - crisis_id/source_url/headline_hash
    are filled in by the caller, not Groq, same split as
    PromiseEvidenceStanceSchema."""

    narrative: str
    genz_narrative: Optional[str] = None


class DataStoryGroqSchema(BaseModel):
    """Groq-only output for the Data Stories module (see
    groq_processor._DATA_STORY_SYSTEM_PROMPT /
    pipeline.data_story_aqi). Groq is given a plain-language summary of
    numbers already computed in code (never raw data it could misread) and
    only writes the narrative framing - chart_data/headline_stat are built
    by the caller directly from the dataset, not by Groq."""

    title: str
    genz_title: Optional[str] = None
    narrative_summary: str
    genz_summary: Optional[str] = None


class CourtLevel(str, Enum):
    SUPREME_COURT = "supreme_court"
    HIGH_COURT = "high_court"
    NGT = "ngt"
    NCLT = "nclt"
    NCLAT = "nclat"
    CBI_COURT = "cbi_court"
    OTHER = "other"


class CourtCaseCategory(str, Enum):
    CONSTITUTIONAL = "constitutional"
    CRIMINAL = "criminal"
    ENVIRONMENTAL = "environmental"
    CORPORATE = "corporate"
    ELECTORAL = "electoral"
    PIL = "pil"
    SERVICE_MATTER = "service_matter"
    OTHER = "other"


class CourtCaseSchema(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    case_title: str
    case_number: Optional[str] = None
    case_slug: str
    is_new_case: bool = True
    court: CourtLevel
    high_court_state: Optional[str] = None
    case_category: CourtCaseCategory
    petitioner: str
    respondent: str
    core_legal_question: str
    petitioner_argument: str
    respondent_argument: Optional[str] = None
    last_hearing_date: Optional[str] = None
    last_hearing_outcome: Optional[str] = None
    next_hearing_date: Optional[str] = None
    current_order: Optional[str] = None
    key_documents: list[str] = Field(default_factory=list)
    impact_if_petitioner_wins: str
    impact_if_respondent_wins: str
    headline_plain: str
    ai_summary: str
    key_facts: list[str] = Field(default_factory=list)
    follow_up_trigger: Optional[str] = None

    source_url: str = ""
    headline_hash: Optional[str] = None
    last_updated: datetime = Field(default_factory=datetime.utcnow)


class ScienceField(str, Enum):
    SPACE = "space"
    BIOLOGY = "biology"
    PHYSICS = "physics"
    CHEMISTRY = "chemistry"
    ENVIRONMENT = "environment"
    MEDICINE = "medicine"
    MATERIALS = "materials"
    OTHER = "other"


class ScienceResearchReportSchema(BaseModel):
    """One-shot extraction, same shape family as AiTechReportSchema - a
    research/science article write-up, not a living record. Runs on
    MODEL_FAST (see groq_processor.process_science_research)."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    field: ScienceField
    institution: Optional[str] = None
    india_relevance: bool = False
    what_this_means: Optional[str] = None
    headline_plain: str
    genz_summary: Optional[str] = None
    key_facts: list[str] = Field(default_factory=list)

    source_url: str = ""
    headline_hash: Optional[str] = None
    processed_at: datetime = Field(default_factory=datetime.utcnow)


class DataStorySchema(BaseModel):
    """A point-in-time narrative snapshot generated from a public dataset
    (see pipeline behind fetchers.data_gov_in) - not a living record, so no
    slug-based upsert, just headline_hash dedup like ScienceResearchReportSchema."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    slug: Optional[str] = None
    title: str
    genz_title: Optional[str] = None
    dataset_source: str
    headline_stat: Optional[str] = None
    narrative_summary: str
    genz_summary: Optional[str] = None
    chart_data: list[dict] = Field(default_factory=list)

    headline_hash: Optional[str] = None
    published_at: datetime = Field(default_factory=datetime.utcnow)


class SlowCrisisCategory(str, Enum):
    WATER = "water"
    AIR_POLLUTION = "air_pollution"
    GROUNDWATER = "groundwater"
    HEALTHCARE_CAPACITY = "healthcare_capacity"
    EDUCATION_DROPOUT = "education_dropout"
    JUDICIARY_DELAY = "judiciary_delay"
    INFRASTRUCTURE = "infrastructure"
    HOUSING_AFFORDABILITY = "housing_affordability"


class SlowCrisisSeverity(str, Enum):
    STABLE = "stable"
    WORSENING = "worsening"
    IMPROVING = "improving"
    CRITICAL = "critical"


class SlowCrisisSchema(BaseModel):
    """A living record (like GovtPromiseSchema), keyed on crisis_slug.
    current_severity is computed by pure code from crisis_data_points (see
    pipeline.slow_crisis_quant._compute_severity) - NEVER by Groq. Groq's
    only role for this table is narrative/context, never the number or the
    severity verdict itself."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    crisis_slug: str
    title: str
    category: SlowCrisisCategory
    region: Optional[str] = None
    description: Optional[str] = None
    genz_description: Optional[str] = None
    current_severity: Optional[SlowCrisisSeverity] = None
    last_computed_at: Optional[datetime] = None
    data_source: Optional[str] = None


class CrisisDataPointSchema(BaseModel):
    """One quantitative reading for a tracked slow crisis. value/unit come
    directly from the official dataset the Track 1 job pulls - never from
    Groq (see pipeline.slow_crisis_quant module docstring)."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    crisis_id: uuid.UUID
    value: float
    unit: str
    recorded_date: str
    source_url: str = ""
    note: Optional[str] = None


class CrisisNarrativeUpdateSchema(BaseModel):
    """One Track 2 (narrative) update: a news article matched to a tracked
    slow crisis, summarized by Groq - context only, never a data point."""

    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    crisis_id: uuid.UUID
    narrative: str
    genz_narrative: Optional[str] = None
    source_url: str = ""
    headline_hash: Optional[str] = None
    generated_at: datetime = Field(default_factory=datetime.utcnow)
