"""Entry point for the NewsUp ingestion pipeline. Run as:

    python src/main.py --sources news,reddit,social,youtube

Fetches raw content from Google News, NewsData.io, Mediastack, direct outlet
RSS feeds, general-news subreddits, crisis-hunting subreddits, Twitter (via
RSSHub), and/or YouTube transcripts concurrently, dedupes against existing
Supabase rows (fast exact-match hash check first, then pgvector semantic
similarity) before spending a Groq call, sends new items to Groq for
structured extraction, and inserts the result into Supabase. `--sources` lets
the four cron workflows (news_cron.yml, reddit_cron.yml, social_cron.yml,
youtube_cron.yml) each run a subset — no persistent state between runs beyond
what's in Supabase.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import random
import re
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

from ai_processor.embeddings import embed_text
from ai_processor.groq_processor import (
    MODEL_COMPLEX,
    MODEL_FAST,
    process_ai_tech,
    process_claim_v2,
    process_court_case,
    process_crisis_classification,
    process_govt_promise,
    process_raw_text_to_schema,
    process_science_research,
    process_stats_extraction,
    process_student_crisis,
)
from database.outlet_credibility import lookup_credibility
from database.supabase_client import (
    append_crisis_evidence,
    append_fact_check_source,
    bump_crisis_report,
    compute_importance_score,
    count_recent_student_crisis_reports,
    find_by_headline_hash,
    find_recent_crisis_titles,
    find_recent_public_events,
    find_similar_crisis_report,
    find_similar_fact_check,
    insert_ai_tech_report,
    insert_crisis_event,
    insert_crisis_report,
    insert_fact_check,
    insert_fact_check_v2,
    insert_outlet_source,
    insert_public_event,
    insert_science_research_report,
    insert_statistics,
    insert_student_crisis_report,
    merge_lookback_days,
    recompute_coverage,
    upsert_court_case,
    upsert_govt_promise,
)
from fetchers.arxiv import fetch_all_arxiv
from fetchers.fetch_youtube import fetch_all_youtube
from fetchers.google_news import fetch_all_google_news
from fetchers.imd_alerts import fetch_all_imd_alerts
from fetchers.mediastack import fetch_all_mediastack
from fetchers.newsdata import fetch_all_newsdata
from fetchers.prs_legislative import fetch_all_prs_bills
from fetchers.reddit import fetch_all_reddit_crises
from fetchers.reddit_news import fetch_all_reddit_news
from fetchers.rss_feeds import fetch_all_businessline, fetch_all_rss_outlets
from fetchers.sansad_elibrary import fetch_all_elibrary_records
from fetchers.twitter_rsshub import fetch_all_twitter
from fetchers.usgs_earthquakes import fetch_all_usgs_earthquakes
from models.schemas import (
    CrisisEventSchema,
    CrisisEventSeverity,
    CrisisEventStatus,
    CrisisEventType,
    CrisisReportSchema,
    EvidenceItem,
    FactCheckSchema,
    RawContentItem,
    SourceRef,
)
from pipeline.promise_evidence import process_promise_evidence_item
from pipeline.promise_reverification import run_promise_reverification
from pipeline.public_events import build_public_event, classify_event_type, find_or_merge_public_event
from pipeline.data_story_aqi import run_data_story_aqi_update
from pipeline.slow_crisis_narrative import process_slow_crisis_narrative_item
from pipeline.slow_crisis_quant import run_slow_crisis_quant_update
from utils.fuzzy_match import is_duplicate_title
from utils.headline_hash import headline_hash

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("newsup.pipeline")

# Seconds to wait between Groq calls to stay comfortably within the free-tier
# requests-per-minute limit. Adjust if your quota changes.
GROQ_CALL_DELAY_SECONDS = 2

# Hard cap so a single viral topic (e.g. hundreds of near-duplicate Google News
# results) can't blow past the GitHub Actions job timeout. Anything left over
# is simply picked up on the next cron run.
MAX_ITEMS_PER_RUN = 85

# Per-source share of MAX_ITEMS_PER_RUN within fetch_all_news_sources, so a
# high-volume source (Google News, RSS) can't crowd out a low-volume one
# (arXiv, eLibrary) that happens to sort later in gather order. Weighted by
# rough source importance/volume rather than split evenly. Google News was
# trimmed from 15 to 12 to make room for businessline_rss (8) — BusinessLine
# is higher-signal for India policy/science than Google News. Total = 85.
SOURCE_CAPS = {
    "google_news": 12,  # reduced from 15
    "newsdata": 15,
    "mediastack": 10,
    "rss_outlets": 15,
    "reddit_news": 5,
    "prs_bills": 10,
    "elibrary_records": 5,
    "arxiv": 5,
    "businessline_rss": 8,  # new
}

# Cosine similarity above which a new item is treated as a near-duplicate of
# an existing row (merged as evidence) instead of triggering a fresh Groq call.
SIMILARITY_THRESHOLD = 0.85

# The 4 expansion modules (student_crisis, court_tracker, govt_promise,
# ai_tech) are additive Groq calls on top of the existing fact_check/crisis
# pipeline — two of them (student_crisis, court_tracker) run on MODEL_COMPLEX
# (70b), the most expensive model. On a busy run a large fraction of articles
# can match one of the four keyword lists, which would multiply Groq spend
# per run. EXPANSION_MODULE_SAMPLE_RATE throttles this independently of
# GROQ_CALL_DELAY_SECONDS/MAX_ITEMS_PER_RUN: each matched item is only
# actually sent to Groq with this probability, so token spend scales down
# without touching which items are dedup-eligible or affecting the rest of
# the pipeline for that item. 1.0 (default) means no throttling.
EXPANSION_MODULE_SAMPLE_RATE = max(0.0, min(1.0, float(os.environ.get("EXPANSION_MODULE_SAMPLE_RATE", "1.0"))))

# NEET has the most ambient news volume of any tracked exam and was crowding
# out JEE/CUET/UPSC/GATE/CAT/CLAT/NDA/board-exam coverage in the student
# crisis feed. Once this many NEET-tagged items have been ingested in the
# last 24h, further NEET articles are skipped *before* the Groq call (see
# _is_neet_item / process_expansion_module below) rather than after, since
# exam identity is a Groq output field and gating on it post-call would
# waste the very call this quota exists to save. Lowered from 4 to 2 -
# fetchers/google_news.py and newsdata.py's DEFAULT_QUERIES were also
# 100% exam-scoped (no general-news query existed at all) and concatenated
# results query-by-query before this pipeline's per-run item cap sliced the
# list, so NEET dominance was baked in well upstream of this quota; fixing
# that raises how much non-exam volume even reaches this gate, so this can
# now afford to bind tighter without starving NEET coverage entirely.
NEET_DAILY_QUOTA = int(os.environ.get("NEET_DAILY_QUOTA", "2"))


async def fetch_all_news_sources() -> list[RawContentItem]:
    """Aggregates every fact-check-routed news source behind the "news" cron
    bucket: Google News search queries, NewsData.io, Mediastack, direct
    outlet RSS feeds (PIB/Hindu/Indian Express/PRS/BBC World/Hindu Science),
    The Hindu BusinessLine (its own gather entry/SOURCE_CAPS slot, not folded
    into the rss_outlets bucket, since it's weighted higher-signal for India
    policy/science than the general outlet feeds), general news-link
    subreddits (r/india, r/worldnews — not the
    crisis-hunting subreddits under fetch_all_reddit_crises, which stays
    under the separate "reddit" bucket below), the Government Promises
    Tracker's evidence-trail sources (PRS Legislative, sansad.in eLibrary),
    and arXiv (science_research) — all ride this same hourly cadence since
    none of these update faster than news does, but process_and_store()/
    process_expansion_module() route the evidence-trail and arxiv sources
    around the normal fact_check/crisis pipeline (see _PROMISE_EVIDENCE_SOURCES
    and the item.source == "arxiv" check), same as _GOV_ALERT_SOURCES does
    for IMD/USGS.

    Each source is capped to its own weighted share of MAX_ITEMS_PER_RUN (see
    SOURCE_CAPS) *before* flattening, so a high-volume source like Google
    News can't consume the entire per-run budget and starve low-volume
    sources like arXiv/PRS/eLibrary that always land later in the list.

    return_exceptions=True so one source blowing up (a hung connection past
    its own internal timeout, an unhandled exception in a new fetcher, etc.)
    can't take down every other source's items with it — each fetcher is
    already responsible for catching its own expected errors and returning
    [] (see e.g. fetchers/arxiv.py's _fetch_one), this is just the backstop.
    """
    results = await asyncio.gather(
        fetch_all_google_news(),
        fetch_all_newsdata(),
        fetch_all_mediastack(),
        fetch_all_rss_outlets(),
        fetch_all_reddit_news(),
        fetch_all_prs_bills(),
        fetch_all_elibrary_records(),
        fetch_all_arxiv(),
        fetch_all_businessline(),
        return_exceptions=True,
    )
    source_order = [
        "google_news", "newsdata", "mediastack", "rss_outlets",
        "reddit_news", "prs_bills", "elibrary_records", "arxiv",
        "businessline_rss",
    ]
    items: list[RawContentItem] = []
    for source_name, batch in zip(source_order, results):
        if isinstance(batch, BaseException):
            logger.warning("Source %r failed with an unhandled exception: %s", source_name, batch)
            continue
        items.extend(batch[:SOURCE_CAPS[source_name]])
    return items


async def fetch_all_gov_alerts() -> list[RawContentItem]:
    """Official government sources — IMD weather alerts and USGS earthquake
    reports. Structured data, no LLM needed to classify it; see
    process_gov_alert, which routes items from this bucket around the usual
    Groq classification pipeline.
    """
    results = await asyncio.gather(fetch_all_imd_alerts(), fetch_all_usgs_earthquakes())
    return [item for batch in results for item in batch]


SOURCE_FETCHERS = {
    "news": fetch_all_news_sources,
    "reddit": fetch_all_reddit_crises,
    "social": fetch_all_twitter,
    "youtube": fetch_all_youtube,
    "gov_alerts": fetch_all_gov_alerts,
}

# Weekly jobs are architecturally different from SOURCE_FETCHERS: they don't
# fetch new RawContentItems and run them through collect_raw_items/
# process_and_store — they batch over *existing* Supabase rows (tracked
# govt_promises + their accumulated promise_evidence). Kept as a separate
# dict rather than shoehorned into SOURCE_FETCHERS so main() can dispatch
# each kind correctly; --sources validation checks both (see parse_args/main
# below), so the CLI invocation stays uniform:
# `python src/main.py --sources promise_verification`.
WEEKLY_JOBS = {
    "promise_verification": run_promise_reverification,
    # Monthly cadence despite the dict name - see WEEKLY_JOBS's comment
    # above; matches the source dataset's own update frequency
    # (CPCB/data.gov.in AQI readings don't need a weekly pull either, but
    # daily is cheap and gives cleaner trend data for _compute_severity).
    "slow_crisis_quant": run_slow_crisis_quant_update,
    # True monthly cadence - Data Stories are point-in-time narrative
    # snapshots, unlike slow_crisis_quant's daily trend-building pull.
    "data_stories_aqi": run_data_story_aqi_update,
    # underreported_topics / underreported_topics_narrative removed here:
    # pipeline/underreported_topics.py was never committed to this repo (it
    # exists only as an untracked local file), and imports 3 functions that
    # don't exist elsewhere in the codebase either. Re-add both entries once
    # that module and its fetcher dependencies are actually finished and
    # committed together.
}

_GOV_ALERT_SOURCES = {"imd", "usgs"}

# Government Promises Tracker evidence-trail sources (see
# fetchers.prs_legislative / fetchers.sansad_elibrary) — routed around the
# fact_check/crisis pipeline in process_and_store(), same treatment as
# _GOV_ALERT_SOURCES, but into pipeline.promise_evidence instead.
_PROMISE_EVIDENCE_SOURCES = {"prs_legislative", "sansad_elibrary"}

# CrisisEventType doesn't carry the general-purpose buckets (court_case,
# economy, ...) PublicEventType does, since those never come from an
# official disaster/earthquake feed — fall back to a sane per-source default
# when classify_event_type() can't find a specific match.
_GOV_ALERT_FALLBACK_TYPE = {"imd": CrisisEventType.WEATHER_ALERT, "usgs": CrisisEventType.EARTHQUAKE}


def _gov_alert_event_type(item: RawContentItem) -> CrisisEventType:
    guessed = classify_event_type(item.title, item.text)
    try:
        return CrisisEventType(guessed.value)
    except ValueError:
        return _GOV_ALERT_FALLBACK_TYPE[item.source]


def _gov_alert_severity(item: RawContentItem) -> CrisisEventSeverity:
    if item.source == "usgs":
        match = re.search(r"M(\d+(?:\.\d+)?)", item.title)
        magnitude = float(match.group(1)) if match else 0.0
        if magnitude >= 6:
            return CrisisEventSeverity.HIGH
        if magnitude >= 4.5:
            return CrisisEventSeverity.MEDIUM
        return CrisisEventSeverity.LOW

    text = item.text.lower()
    if "extreme" in text or "severe" in text:
        return CrisisEventSeverity.HIGH
    if "moderate" in text:
        return CrisisEventSeverity.MEDIUM
    return CrisisEventSeverity.LOW


def process_gov_alert(item: RawContentItem) -> None:
    """Official-source path: skips Groq entirely (structured data doesn't
    need LLM extraction) and writes straight into crises + public_events,
    marked verified since it's a direct government feed rather than a news
    article about one.
    """
    item_hash = headline_hash(item.title)
    if find_by_headline_hash("crises", item_hash) is not None:
        logger.info("Skipping duplicate gov alert (headline hash match): %s", item.title[:80])
        return

    result = CrisisEventSchema(
        type=_gov_alert_event_type(item),
        title=item.title,
        severity=_gov_alert_severity(item),
        status=CrisisEventStatus.ONGOING,
        trigger_keyword=item.source,
        tags=[item.source],
        description=item.text[:500],
        affects_students=False,
        source_headline=item.title,
        headline_hash=item_hash,
    )
    crisis_id = insert_crisis_event(result.model_dump(mode="json"))
    if crisis_id is None:
        return

    try:
        importance = compute_importance_score(
            severity=result.severity.value,
            affects_students=False,
            total_outlets=0,
            source_table="crises",
        )
        public_event = build_public_event(
            item,
            source_table="crises",
            source_id=crisis_id,
            embedding=embed_text(item.title),
            headline_hash=item_hash,
            importance_score=importance,
            crisis_event=result,
        )
        public_event["verified"] = True
        upsert_or_merge_public_event(public_event, item)
    except Exception:
        logger.exception("Failed to build public event for gov alert %s", crisis_id)


def classify_content_type(item: RawContentItem) -> str:
    """Heuristic: which schema the AI processor should extract for this item.

    Posts from the crisis-hunting subreddits (source == "reddit", see
    fetchers/reddit.py) are grassroots signals of an ongoing crisis (leaks,
    protests, inaction), so they're routed to CrisisReportSchema. Everything
    else — Google News, NewsData.io, Mediastack, direct outlet RSS, general
    news-link subreddits (source == "reddit_news"), official Twitter
    statements, and YouTube transcripts (press briefings, hearings) — usually
    centers on a single checkable claim, so it's routed to FactCheckSchema.
    """
    if item.source == "reddit":
        return "crisis_report"
    return "fact_check"


# ---------------------------------------------------------------------------
# Crisis classifier / stats extractor routing — additive to
# classify_content_type() above, not a replacement. An item still goes
# through the existing fact_check/crisis_report pipeline regardless of what
# route_article() returns; a "crisis" or "stats" match additionally spends one
# extra Groq call to also tag it into the new crises / statistics tables (see
# supabase/migrations/0008_crisis_events_and_statistics.sql).
# ---------------------------------------------------------------------------

CRISIS_KEYWORDS = [
    "NEET", "JEE", "UPSC", "paper leak", "question paper leaked",
    "exam postponed", "exam rescheduled",
    "student suicide", "student suicides", "spate of suicides", "Kota student",
    "flood", "flooding", "flash flood", "cyclone", "heatwave", "heat wave",
    "earthquake", "IMD alert", "rain alert", "orange alert", "weather warning",
    "rape", "violence against women", "AI regulation", "ChatGPT",
]

# "victims" and "per year" were dropped — too generic (matched almost any
# crime/finance article regardless of whether it actually contained
# statistics); the remaining terms are specific enough on their own.
STATS_KEYWORDS = [
    "NCRB", "crime statistics", "suicides reported", "cases registered",
]


def route_article(headline: str, summary: str) -> str:
    """Which of the new crisis-classifier / stats-extractor prompts (if
    either) this item's headline+summary matches. Crisis keywords are
    checked first since a crisis headline can also contain a stats-like word
    (e.g. "cases registered") without being a stats report.
    """
    text = f"{headline} {summary}".lower()
    if any(k.lower() in text for k in CRISIS_KEYWORDS):
        return "crisis"
    if any(k.lower() in text for k in STATS_KEYWORDS):
        return "stats"
    return "factcheck"


# ---------------------------------------------------------------------------
# Expansion modules — student crisis / court tracker / govt promises /
# AI & tech (see truthlens_expansion_prompt.md Part 0). Additive to
# route_article() above: an item still goes through the existing
# fact_check/crisis_report/crisis/stats pipeline regardless of what
# route_expansion_module() returns; a match here spends one extra Groq call
# to also write a row into one of the four new module tables.
# ---------------------------------------------------------------------------

STUDENT_CRISIS_KEYWORDS = [
    # Exams — not just NEET
    "NEET", "JEE", "CUET", "UPSC", "GATE", "CAT", "CLAT", "NDA",
    "board exam", "class 10", "class 12", "UP board", "CBSE", "ICSE",
    "exam paper", "paper leak", "question paper", "answer key",
    "re-exam", "cancelled exam", "postponed exam",
    # Student distress
    "student suicide", "student death", "student protest",
    "coaching center", "kota suicide", "student mental health",
    "study pressure", "exam stress", "student arrested",
    "rustication", "college expelled", "university protest",
    "scholarship cancelled", "student loan",
]

GOVT_PROMISE_KEYWORDS = [
    "inaugurated", "foundation stone", "launched", "announced",
    "budget allocation", "scheme", "mission", "yojana",
    "metro line", "highway", "expressway", "smart city",
    "semiconductor", "AI mission", "Digital India",
    "election promise", "manifesto", "deadline extended",
    "project delayed", "cost overrun", "tender issued",
    "DPIIT", "NITI Aayog", "PLI scheme",
    # Added for the evidence-trail/re-verification expansion: promise
    # tracking coverage that the original keyword list didn't catch.
    "poll promise", "on track", "behind schedule",
    "CAG report", "parliamentary question", "deadline missed",
]

COURT_KEYWORDS = [
    "Supreme Court", "High Court", "PIL", "contempt of court",
    "constitutional bench", "CJI", "Chief Justice",
    "stay order", "bail granted", "bail denied",
    "verdict", "judgment", "chargesheet", "FIR",
    "corporate lawsuit", "environmental litigation",
    "NGT", "National Green Tribunal",
    "ED", "CBI", "NIA", "SFIO",
]

# Scoped to air pollution this session - the only Slow Crisis category with
# a live Track 1 quantitative source (see pipeline.slow_crisis_quant).
# Widen alongside each new category's Track 1 source once verified live.
SLOW_CRISIS_KEYWORDS = [
    "air quality", "AQI", "smog", "air pollution",
    "pollution levels", "particulate matter", "PM2.5", "PM10",
    "GRAP", "graded response action plan", "stubble burning",
]

AI_TECH_KEYWORDS = [
    "artificial intelligence", "AI model", "large language model",
    "GPT", "Claude", "Gemini", "Llama", "open source AI",
    "AI regulation", "AI policy", "AI Act",
    "chipmaker", "GPU", "Nvidia", "semiconductor fab",
    "deepfake", "AI-generated", "synthetic media",
    "robotics", "autonomous vehicle", "drone policy",
    "data center", "cloud computing", "quantum computing",
    "AI startup", "unicorn", "AI funding",
    "IndiaAI", "C-DAC", "IIT AI lab",
]

# Items from source="arxiv" (see fetchers/arxiv.py) route straight to
# science_research by source, bypassing this keyword list entirely - they're
# unambiguously research papers. These keywords exist for the Hindu Science
# RSS feed (rss_feeds.py DEFAULT_FEEDS), which mixes research write-ups
# with general science journalism.
SCIENCE_RESEARCH_KEYWORDS = [
    "ISRO", "space mission", "satellite launch", "Chandrayaan", "Gaganyaan",
    "research paper", "study published", "scientists discover",
    "clinical trial", "vaccine research", "gene therapy",
    "climate research", "IPCC report", "IISc", "CSIR", "DST", "DBT",
    "physics breakthrough", "materials science", "quantum research",
]


def _keyword_matches(keywords: list[str], text: str) -> bool:
    """Word-boundary match, not plain substring. The spec's COURT_KEYWORDS
    list includes bare short acronyms ("ED", "CBI", "NIA", "FIR") that, as a
    naive substring check, false-positive inside ordinary words — "ED" alone
    matches "relat-ED", "affect-ED", "delay-ED", "mention-ED", silently
    routing routine articles into the court-tracker module. \b keeps the
    exact keyword list from the spec but only matches it as a whole word/phrase.
    """
    return any(re.search(rf"\b{re.escape(k.lower())}\b", text) for k in keywords)


def _is_neet_item(headline: str, body: str) -> bool:
    """Cheap pre-Groq check for the NEET_DAILY_QUOTA gate (see
    process_expansion_module) - deliberately just a word-boundary "neet"
    match on the raw text, same technique as _keyword_matches, since NEET is
    an unambiguous token in Indian news text and this needs to run before
    spending a Groq call, when the only information available is raw
    headline/body text, not Groq's structured exam_or_context output."""
    return _keyword_matches(["NEET"], f"{headline}\n{body}".lower())


def route_expansion_module(headline: str, body: str) -> tuple[str, Optional[str]]:
    """Part 0 routing table: returns (module_name, model_to_use), matching
    the source spec's route_article() signature. Priority order:
    student_crisis > court_tracker > govt_promise > slow_crisis > ai_tech >
    science_research. Returns ("none", None) if nothing matches.

    Note: arxiv-sourced items skip this function entirely and route straight
    to science_research in process_expansion_module (unambiguous by source,
    no keyword match needed) — the science_research check here only ever
    fires for keyword-matched items from other sources (e.g. Hindu Science RSS).
    data_stories is never routed from articles at all (see
    fetchers/data_gov_in.py) so it never appears in this function.

    model_to_use reflects the actual Groq model names this pipeline uses
    (MODEL_COMPLEX / MODEL_FAST, see groq_processor.py), not the spec's
    literal "llama3-70b-8192" / "llama3-8b-8192" — those specific model
    names have since been retired by Groq, which is exactly why this
    codebase already resolves model choice through env-overridable
    MODEL_COMPLEX/MODEL_FAST constants instead of hardcoding a model id.
    """
    text = f"{headline} {body}".lower()

    if _keyword_matches(STUDENT_CRISIS_KEYWORDS, text):
        return ("student_crisis", MODEL_COMPLEX)
    if _keyword_matches(COURT_KEYWORDS, text):
        return ("court_tracker", MODEL_COMPLEX)
    if _keyword_matches(GOVT_PROMISE_KEYWORDS, text):
        return ("govt_promise", MODEL_FAST)
    if _keyword_matches(SLOW_CRISIS_KEYWORDS, text):
        return ("slow_crisis", MODEL_FAST)
    if _keyword_matches(AI_TECH_KEYWORDS, text):
        return ("ai_tech", MODEL_FAST)
    if _keyword_matches(SCIENCE_RESEARCH_KEYWORDS, text):
        return ("science_research", MODEL_FAST)
    return ("none", None)


def process_expansion_module(item: RawContentItem, text: str) -> None:
    """Runs route_expansion_module() and, on a match, spends one Groq call
    against the matched module's prompt and writes the result into that
    module's table. Independent of process_new_taxonomies (crisis/stats)
    and the fact_check/crisis_report pipeline in process_and_store — all
    three can fire for the same item.
    """
    if item.source == "arxiv":
        module = "science_research"
    else:
        module, _model = route_expansion_module(item.title, item.text[:1000])
    if module == "none":
        return

    if EXPANSION_MODULE_SAMPLE_RATE < 1.0 and random.random() > EXPANSION_MODULE_SAMPLE_RATE:
        logger.info(
            "Sampled out of expansion module %r (rate=%.2f): %s", module, EXPANSION_MODULE_SAMPLE_RATE, item.title[:80]
        )
        return

    item_hash = headline_hash(item.title)

    if module == "student_crisis":
        if _is_neet_item(item.title, item.text[:1000]) and count_recent_student_crisis_reports("NEET") >= NEET_DAILY_QUOTA:
            logger.info("Skipping NEET item over daily quota (%d): %s", NEET_DAILY_QUOTA, item.title[:80])
            return
        if find_by_headline_hash("student_crisis_reports", item_hash) is not None:
            logger.info("Skipping duplicate student crisis report (headline hash match): %s", item.title[:80])
            return
        result = process_student_crisis(item.title, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.source_url = item.url
            result.headline_hash = item_hash
            insert_student_crisis_report(result.model_dump(mode="json"))

        # Secondary module: a student_crisis item can also carry a court
        # angle (e.g. a paper-leak case that reaches the High Court). Capped
        # at exactly this one extra module — not a general secondary-module
        # mechanism — so a single article still spends at most 2 Groq calls,
        # never all of them. Not persisted anywhere (no secondary_module
        # column); this just runs the existing court_tracker branch logic
        # for the same item, in-memory only.
        if _keyword_matches(COURT_KEYWORDS, f"{item.title} {item.text[:1000]}".lower()):
            if find_by_headline_hash("court_cases", item_hash) is None:
                court_result = process_court_case(item.title, text)
                time.sleep(GROQ_CALL_DELAY_SECONDS)
                if court_result is not None:
                    court_result.source_url = item.url
                    court_result.headline_hash = item_hash
                    upsert_court_case(court_result.model_dump(mode="json"))
            else:
                logger.info("Skipping duplicate secondary court case (headline hash match): %s", item.title[:80])

    elif module == "ai_tech":
        if find_by_headline_hash("ai_tech_reports", item_hash) is not None:
            logger.info("Skipping duplicate AI/tech report (headline hash match): %s", item.title[:80])
            return
        result = process_ai_tech(item.title, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.source_url = item.url
            result.headline_hash = item_hash
            insert_ai_tech_report(result.model_dump(mode="json"))

    elif module == "science_research":
        if find_by_headline_hash("science_research_reports", item_hash) is not None:
            logger.info("Skipping duplicate science research report (headline hash match): %s", item.title[:80])
            return
        result = process_science_research(item.title, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.source_url = item.url
            result.headline_hash = item_hash
            insert_science_research_report(result.model_dump(mode="json"))

    elif module == "slow_crisis":
        # Multi-step (fuzzy-match against tracked crises, then one Groq
        # call), unlike the single-call branches above, so it's a real
        # pipeline module rather than an inline branch.
        process_slow_crisis_narrative_item(item, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)

    elif module == "govt_promise":
        result = process_govt_promise(item.title, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.source_url = item.url
            result.headline_hash = item_hash
            upsert_govt_promise(result.model_dump(mode="json"))

    elif module == "court_tracker":
        result = process_court_case(item.title, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.source_url = item.url
            result.headline_hash = item_hash
            upsert_court_case(result.model_dump(mode="json"))


def upsert_or_merge_public_event(public_event: dict, item: RawContentItem) -> Optional[str]:
    """Write a public_events row, first checking whether a recent row of the
    same event_type/place already describes this event (by fuzzy title
    match) and folding this source into it instead of minting a duplicate
    card — see pipeline.public_events.find_or_merge_public_event. Falls back
    to the (source_table, source_id) upsert for genuinely new events.
    """
    try:
        merged_id = find_or_merge_public_event(public_event, item)
        if merged_id is not None:
            return merged_id
    except Exception:
        logger.exception("Fuzzy public-event merge check failed for %s; inserting normally", item.url)
    return insert_public_event(public_event)


def process_new_taxonomies(item: RawContentItem, text: str) -> None:
    """Additive crisis-classifier / stats-extractor pass — independent of the
    existing fact_checks/crisis_reports pipeline in process_and_store below.
    Only spends an extra Groq call for items route_article() flags; most
    items fall through as "factcheck" and cost nothing extra here.
    """
    route = route_article(item.title, item.text[:1000])

    if route == "crisis":
        # Fast exact-match dedup pre-filter first (cheapest check).
        item_hash = headline_hash(item.title)
        if find_by_headline_hash("crises", item_hash) is not None:
            logger.info("Skipping duplicate crisis classification (headline hash match): %s", item.title[:80])
            return

        # Fuzzy pre-filter: catches differently-worded headlines about the
        # same event (e.g. "Heavy rain floods UP" vs "UP flooding hits
        # Lucknow") that the exact hash above can't. event_type isn't known
        # yet at this point, so this matches against all recent crises and
        # relies on title similarity to separate unrelated stories.
        try:
            since = (datetime.now(timezone.utc) - timedelta(days=4)).isoformat()
            candidates = find_recent_crisis_titles(since)
            fuzzy_match = next((c for c in candidates if is_duplicate_title(item.title, c["title"])), None)
        except Exception:
            logger.exception("Fuzzy crisis dedup check failed for %s; proceeding to Groq anyway", item.url)
            fuzzy_match = None

        if fuzzy_match is not None:
            bump_crisis_report(fuzzy_match["id"])
            logger.info("Merged into existing crisis %s by fuzzy title match: %s", fuzzy_match["id"], item.title[:80])
            return

        result = process_crisis_classification(item.title, item.text[:1000])
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.headline_hash = item_hash
            crisis_id = insert_crisis_event(result.model_dump(mode="json"))
            if crisis_id is not None:
                try:
                    importance = compute_importance_score(
                        severity=result.severity.value,
                        affects_students=result.affects_students,
                        total_outlets=0,
                        source_table="crises",
                    )
                    public_event = build_public_event(
                        item,
                        source_table="crises",
                        source_id=crisis_id,
                        embedding=embed_text(item.title),
                        headline_hash=item_hash,
                        importance_score=importance,
                        crisis_event=result,
                    )
                    upsert_or_merge_public_event(public_event, item)
                except Exception:
                    logger.exception("Failed to build public event for crisis %s", crisis_id)
    elif route == "stats":
        stats = process_stats_extraction(text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if stats:
            insert_statistics([s.model_dump(mode="json") for s in stats])


async def collect_raw_items(sources: set[str]) -> list[RawContentItem]:
    fetchers = [SOURCE_FETCHERS[name] for name in sources]
    results = await asyncio.gather(*(fetcher() for fetcher in fetchers))
    items = [item for batch in results for item in batch]
    logger.info("Collected %d raw items from sources=%s", len(items), sorted(sources))
    return items


def record_outlet_and_coverage(
    item: RawContentItem, *, fact_check_id: Optional[str] = None, crisis_report_id: Optional[str] = None
) -> int:
    """Record this item's outlet on outlet_sources and recompute the
    coverage_analysis cache row (see migration 0006). Called for both
    genuinely new rows and merges, so coverage reflects every outlet that
    reported the story, not just the first one. Returns the recomputed
    total_outlets count (0 on failure) — used as a real media-coverage
    signal by pipeline.public_events.build_public_event.
    """
    outlet_name = item.outlet_name or item.origin
    try:
        insert_outlet_source(
            fact_check_id=fact_check_id,
            crisis_report_id=crisis_report_id,
            outlet_name=outlet_name,
            outlet_url=item.url,
            publish_time=(item.published_at or datetime.now(timezone.utc)).isoformat(),
            outlet_credibility_score=lookup_credibility(outlet_name),
        )
        return recompute_coverage(fact_check_id=fact_check_id, crisis_report_id=crisis_report_id)
    except Exception:
        logger.exception("Failed to record outlet/coverage for %s", item.url)
        return 0


def try_merge_by_hash(item: RawContentItem, content_type: str) -> bool:
    """Fast exact-match pre-filter, checked before the embedding computation
    and pgvector lookup in try_merge_into_existing — catches the common case
    of the same wire story reprinted verbatim across outlets without the
    cost of an embedding or Groq call. Returns True if merged.
    """
    table = "fact_checks" if content_type == "fact_check" else "crisis_reports"
    match_id = find_by_headline_hash(table, headline_hash(item.title))
    if match_id is None:
        return False

    if content_type == "fact_check":
        append_fact_check_source(
            match_id,
            {
                "title": item.title,
                "url": item.url,
                "published_at": (item.published_at or datetime.now(timezone.utc)).isoformat(),
            },
        )
        record_outlet_and_coverage(item, fact_check_id=match_id)
    else:
        evidence_url = item.evidence_url or item.url
        evidence_type = "DOCUMENT" if item.evidence_url else "LIVE"
        append_crisis_evidence(match_id, {"title": item.title, "url": evidence_url, "type": evidence_type})
        record_outlet_and_coverage(item, crisis_report_id=match_id)

    logger.info("Merged into existing %s %s by exact headline hash: %s", content_type, match_id, item.title[:80])
    return True


def try_merge_into_existing(item: RawContentItem, content_type: str, embedding: list[float]) -> bool:
    """If a near-duplicate row already exists, append this item as evidence on
    it instead of spending a Groq call. Returns True if merged (caller should
    skip Groq + insert), False if this looks like a genuinely new item.
    """
    if content_type == "fact_check":
        match_id = find_similar_fact_check(embedding, SIMILARITY_THRESHOLD)
        if match_id is None:
            return False
        append_fact_check_source(
            match_id,
            {
                "title": item.title,
                "url": item.url,
                "published_at": (item.published_at or datetime.now(timezone.utc)).isoformat(),
            },
        )
        record_outlet_and_coverage(item, fact_check_id=match_id)
        logger.info("Merged into existing fact check %s: %s", match_id, item.title[:80])
        return True

    match_id = find_similar_crisis_report(embedding, SIMILARITY_THRESHOLD)
    if match_id is None:
        return False
    evidence_url = item.evidence_url or item.url
    evidence_type = "DOCUMENT" if item.evidence_url else "LIVE"
    append_crisis_evidence(match_id, {"title": item.title, "url": evidence_url, "type": evidence_type})
    record_outlet_and_coverage(item, crisis_report_id=match_id)
    logger.info("Merged into existing crisis report %s: %s", match_id, item.title[:80])
    return True


def process_and_store(item: RawContentItem) -> None:
    if item.source in _GOV_ALERT_SOURCES:
        process_gov_alert(item)
        return

    if item.source in _PROMISE_EVIDENCE_SOURCES:
        process_promise_evidence_item(item)
        return

    if item.source == "arxiv":
        process_expansion_module(item, f"{item.title}\n\n{item.text}".strip())
        return

    content_type = classify_content_type(item)
    text = f"{item.title}\n\n{item.text}".strip()
    if not text:
        return

    try:
        process_new_taxonomies(item, text)
    except Exception:
        logger.exception("Crisis/stats classification failed for %s", item.url)

    try:
        process_expansion_module(item, text)
    except Exception:
        logger.exception("Expansion module classification failed for %s", item.url)

    try:
        if try_merge_by_hash(item, content_type):
            return
    except Exception:
        logger.exception("Hash dedup check failed for %s; proceeding to embedding check", item.url)

    embedding = embed_text(item.title)

    try:
        if try_merge_into_existing(item, content_type, embedding):
            return
    except Exception:
        logger.exception("Dedup check failed for %s; proceeding to Groq anyway", item.url)

    result = process_raw_text_to_schema(text, content_type)
    time.sleep(GROQ_CALL_DELAY_SECONDS)

    if result is None:
        return

    result.source_url = item.url
    result.embedding = embedding
    result.headline_hash = headline_hash(item.title)

    if isinstance(result, FactCheckSchema):
        if item.url and not any(s.url == item.url for s in result.sources):
            result.sources.append(
                SourceRef(
                    title=item.title,
                    url=item.url,
                    published_at=item.published_at or datetime.now(timezone.utc),
                )
            )
        fact_check_id = insert_fact_check(result.model_dump(mode="json"))
        if fact_check_id is None:
            return
        total_outlets = record_outlet_and_coverage(item, fact_check_id=fact_check_id)

        try:
            importance = compute_importance_score(
                severity=None,
                affects_students=False,
                total_outlets=total_outlets,
                source_table="fact_checks",
            )
            public_event = build_public_event(
                item,
                source_table="fact_checks",
                source_id=fact_check_id,
                embedding=embedding,
                headline_hash=result.headline_hash,
                importance_score=importance,
                fact_check=result,
            )
            upsert_or_merge_public_event(public_event, item)
        except Exception:
            logger.exception("Failed to build public event for fact check %s", fact_check_id)

        # Legally-safe claim-level fact-check (fact_checks_v2) — only run on
        # genuinely new rows, not merges, same free-tier economy as
        # MODEL_COMPLEX being crisis-report-only.
        v2_result = process_claim_v2(text, fact_check_id)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if v2_result is not None:
            insert_fact_check_v2(v2_result.model_dump(mode="json"))

    elif isinstance(result, CrisisReportSchema):
        # Prefer the durable Supabase-hosted copy (if the reddit fetcher made
        # one) over the original link, which can disappear if the post is
        # deleted. DOCUMENT reflects "archived copy"; LIVE means "still points
        # at the original source".
        evidence_url = item.evidence_url or item.url
        evidence_type = "DOCUMENT" if item.evidence_url else "LIVE"
        if evidence_url and not any(e.url == evidence_url for e in result.evidence_items):
            result.evidence_items.append(
                EvidenceItem(title=item.title, url=evidence_url, type=evidence_type)
            )
        crisis_report_id = insert_crisis_report(result.model_dump(mode="json"))
        if crisis_report_id is None:
            return
        total_outlets = record_outlet_and_coverage(item, crisis_report_id=crisis_report_id)

        try:
            importance = compute_importance_score(
                severity=None,
                affects_students=False,
                total_outlets=total_outlets,
                source_table="crisis_reports",
            )
            public_event = build_public_event(
                item,
                source_table="crisis_reports",
                source_id=crisis_report_id,
                embedding=embedding,
                headline_hash=result.headline_hash,
                importance_score=importance,
                crisis_report=result,
            )
            upsert_or_merge_public_event(public_event, item)
        except Exception:
            logger.exception("Failed to build public event for crisis report %s", crisis_report_id)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="NewsUp ingestion pipeline")
    parser.add_argument(
        "--sources",
        default="news,reddit,social,youtube",
        help=(
            "Comma-separated sources to run this invocation: "
            "news,reddit,social,youtube,gov_alerts,promise_verification,"
            "slow_crisis_quant,data_stories_aqi"
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    requested = {s.strip() for s in args.sources.split(",") if s.strip()}
    valid = SOURCE_FETCHERS.keys() | WEEKLY_JOBS.keys()
    unknown = requested - valid
    if unknown:
        raise SystemExit(f"Unknown source(s): {sorted(unknown)}. Valid: {sorted(valid)}")

    weekly_jobs = requested & WEEKLY_JOBS.keys()
    for job_name in weekly_jobs:
        logger.info("Running weekly job: %s", job_name)
        try:
            WEEKLY_JOBS[job_name]()
        except Exception:
            logger.exception("Weekly job failed: %s", job_name)

    sources = requested & SOURCE_FETCHERS.keys()
    if not sources:
        logger.info("No per-article sources requested; pipeline run complete.")
        return

    items = asyncio.run(collect_raw_items(sources))
    if len(items) > MAX_ITEMS_PER_RUN:
        logger.info(
            "Capping run to %d of %d collected items; the rest will be picked up next run",
            MAX_ITEMS_PER_RUN,
            len(items),
        )
        items = items[:MAX_ITEMS_PER_RUN]

    for item in items:
        try:
            process_and_store(item)
        except Exception:
            logger.exception("Failed to process item: %s", item.url)

    logger.info("Pipeline run complete.")


if __name__ == "__main__":
    main()
