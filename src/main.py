"""Entry point for the NewsUp ingestion pipeline. Run as:

    python src/main.py --sources news,reddit,social,youtube

Fetches raw content from Google News, Reddit, Twitter (via RSSHub), and/or
YouTube transcripts concurrently, semantically dedupes against existing
Supabase rows before spending a Groq call, sends new items to Groq for
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

from ai_processor.embeddings import embed_text
from ai_processor.groq_processor import process_raw_text_to_schema
from database.supabase_client import (
    append_crisis_evidence,
    append_fact_check_source,
    find_similar_crisis_report,
    find_similar_fact_check,
    insert_crisis_report,
    insert_fact_check,
)
from fetchers.fetch_youtube import fetch_all_youtube
from fetchers.google_news import fetch_all_google_news
from fetchers.reddit import fetch_all_reddit_crises
from fetchers.twitter_rsshub import fetch_all_twitter
from models.schemas import (
    CrisisReportSchema,
    EvidenceItem,
    FactCheckSchema,
    RawContentItem,
    SourceRef,
)

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

SOURCE_FETCHERS = {
    "news": fetch_all_google_news,
    "reddit": fetch_all_reddit_crises,
    "social": fetch_all_twitter,
    "youtube": fetch_all_youtube,
}


def classify_content_type(item: RawContentItem) -> str:
    """Heuristic: which schema the AI processor should extract for this item.

    Reddit posts are grassroots signals of an ongoing crisis (leaks, protests,
    inaction), so they're routed to CrisisReportSchema. Google News results,
    official Twitter statements, and YouTube transcripts (press briefings,
    hearings) usually center on a single checkable claim, so they're routed
    to FactCheckSchema.
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
        logger.info("Merged into existing fact check %s: %s", match_id, item.title[:80])
        return True

    match_id = find_similar_crisis_report(embedding, SIMILARITY_THRESHOLD)
    if match_id is None:
        return False
    evidence_url = item.evidence_url or item.url
    evidence_type = "DOCUMENT" if item.evidence_url else "LIVE"
    append_crisis_evidence(match_id, {"title": item.title, "url": evidence_url, "type": evidence_type})
    logger.info("Merged into existing crisis report %s: %s", match_id, item.title[:80])
    return True


def process_and_store(item: RawContentItem) -> None:
    content_type = classify_content_type(item)
    text = f"{item.title}\n\n{item.text}".strip()
    if not text:
        return

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

    if isinstance(result, FactCheckSchema):
        if item.url and not any(s.url == item.url for s in result.sources):
            result.sources.append(
                SourceRef(
                    title=item.title,
                    url=item.url,
                    published_at=item.published_at or datetime.now(timezone.utc),
                )
            )
        insert_fact_check(result.model_dump(mode="json"))

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
        insert_crisis_report(result.model_dump(mode="json"))


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
