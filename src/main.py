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
import time
from datetime import datetime, timezone
from typing import Optional

from ai_processor.embeddings import embed_text
from ai_processor.groq_processor import process_claim_v2, process_raw_text_to_schema
from database.outlet_credibility import lookup_credibility
from database.supabase_client import (
    append_crisis_evidence,
    append_fact_check_source,
    find_by_headline_hash,
    find_similar_crisis_report,
    find_similar_fact_check,
    insert_crisis_report,
    insert_fact_check,
    insert_fact_check_v2,
    insert_outlet_source,
    recompute_coverage,
)
from fetchers.fetch_youtube import fetch_all_youtube
from fetchers.google_news import fetch_all_google_news
from fetchers.mediastack import fetch_all_mediastack
from fetchers.newsdata import fetch_all_newsdata
from fetchers.reddit import fetch_all_reddit_crises
from fetchers.reddit_news import fetch_all_reddit_news
from fetchers.rss_feeds import fetch_all_rss_outlets
from fetchers.twitter_rsshub import fetch_all_twitter
from models.schemas import (
    CrisisReportSchema,
    EvidenceItem,
    FactCheckSchema,
    RawContentItem,
    SourceRef,
)
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


SOURCE_FETCHERS = {
    "news": fetch_all_news_sources,
    "reddit": fetch_all_reddit_crises,
    "social": fetch_all_twitter,
    "youtube": fetch_all_youtube,
}


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


async def collect_raw_items(sources: set[str]) -> list[RawContentItem]:
    fetchers = [SOURCE_FETCHERS[name] for name in sources]
    results = await asyncio.gather(*(fetcher() for fetcher in fetchers))
    items = [item for batch in results for item in batch]
    logger.info("Collected %d raw items from sources=%s", len(items), sorted(sources))
    return items


def record_outlet_and_coverage(
    item: RawContentItem, *, fact_check_id: Optional[str] = None, crisis_report_id: Optional[str] = None
) -> None:
    """Record this item's outlet on outlet_sources and recompute the
    coverage_analysis cache row (see migration 0006). Called for both
    genuinely new rows and merges, so coverage reflects every outlet that
    reported the story, not just the first one.
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
        recompute_coverage(fact_check_id=fact_check_id, crisis_report_id=crisis_report_id)
    except Exception:
        logger.exception("Failed to record outlet/coverage for %s", item.url)


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
    content_type = classify_content_type(item)
    text = f"{item.title}\n\n{item.text}".strip()
    if not text:
        return

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
        record_outlet_and_coverage(item, fact_check_id=fact_check_id)

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
        record_outlet_and_coverage(item, crisis_report_id=crisis_report_id)


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
