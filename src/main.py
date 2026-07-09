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
    process_stats_extraction,
    process_student_crisis,
)
from database.outlet_credibility import lookup_credibility
from database.supabase_client import (
    append_crisis_evidence,
    append_fact_check_source,
    bump_crisis_report,
    compute_importance_score,
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
    insert_statistics,
    insert_student_crisis_report,
    merge_lookback_days,
    recompute_coverage,
    upsert_court_case,
    upsert_govt_promise,
)
from fetchers.fetch_youtube import fetch_all_youtube
from fetchers.google_news import fetch_all_google_news
from fetchers.imd_alerts import fetch_all_imd_alerts
from fetchers.mediastack import fetch_all_mediastack
from fetchers.newsdata import fetch_all_newsdata
from fetchers.reddit import fetch_all_reddit_crises
from fetchers.reddit_news import fetch_all_reddit_news
from fetchers.rss_feeds import fetch_all_rss_outlets
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
from pipeline.public_events import build_public_event, classify_event_type, find_or_merge_public_event
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
MAX_ITEMS_PER_RUN = 80

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


async def fetch_all_news_sources() -> list[RawContentItem]:
    """Aggregates every fact-check-routed news source behind the "news" cron
    bucket: Google News search queries, NewsData.io, Mediastack, direct
    outlet RSS feeds (PIB/Hindu/Indian Express/PRS/BBC World), and general
    news-link subreddits (r/india, r/worldnews — not the crisis-hunting
    subreddits under fetch_all_reddit_crises, which stays under the
    separate "reddit" bucket below).
    """
    results = await asyncio.gather(
        fetch_all_google_news(),
        fetch_all_newsdata(),
        fetch_all_mediastack(),
        fetch_all_rss_outlets(),
        fetch_all_reddit_news(),
    )
    return [item for batch in results for item in batch]


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

_GOV_ALERT_SOURCES = {"imd", "usgs"}

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


def _keyword_matches(keywords: list[str], text: str) -> bool:
    """Word-boundary match, not plain substring. The spec's COURT_KEYWORDS
    list includes bare short acronyms ("ED", "CBI", "NIA", "FIR") that, as a
    naive substring check, false-positive inside ordinary words — "ED" alone
    matches "relat-ED", "affect-ED", "delay-ED", "mention-ED", silently
    routing routine articles into the court-tracker module. \b keeps the
    exact keyword list from the spec but only matches it as a whole word/phrase.
    """
    return any(re.search(rf"\b{re.escape(k.lower())}\b", text) for k in keywords)


def route_expansion_module(headline: str, body: str) -> tuple[str, Optional[str]]:
    """Part 0 routing table: returns (module_name, model_to_use), matching
    the source spec's route_article() signature. Priority order:
    student_crisis > court_tracker > govt_promise > ai_tech. Returns
    ("none", None) if nothing matches.

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
    if _keyword_matches(AI_TECH_KEYWORDS, text):
        return ("ai_tech", MODEL_FAST)
    return ("none", None)


def process_expansion_module(item: RawContentItem, text: str) -> None:
    """Runs route_expansion_module() and, on a match, spends one Groq call
    against the matched module's prompt and writes the result into that
    module's table. Independent of process_new_taxonomies (crisis/stats)
    and the fact_check/crisis_report pipeline in process_and_store — all
    three can fire for the same item.
    """
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
        if find_by_headline_hash("student_crisis_reports", item_hash) is not None:
            logger.info("Skipping duplicate student crisis report (headline hash match): %s", item.title[:80])
            return
        result = process_student_crisis(item.title, text)
        time.sleep(GROQ_CALL_DELAY_SECONDS)
        if result is not None:
            result.source_url = item.url
            result.headline_hash = item_hash
            insert_student_crisis_report(result.model_dump(mode="json"))

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
        help="Comma-separated sources to run this invocation: news,reddit,social,youtube",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    sources = {s.strip() for s in args.sources.split(",") if s.strip()}
    unknown = sources - SOURCE_FETCHERS.keys()
    if unknown:
        raise SystemExit(f"Unknown source(s): {sorted(unknown)}. Valid: {sorted(SOURCE_FETCHERS)}")

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
