"""Entry point for the NewsUp ingestion pipeline. Run as `python src/main.py`.

Fetches raw content from Google News, Reddit, and Twitter (via RSSHub), sends
each item to Groq for structured extraction, and upserts the result into
Supabase. Designed to run to completion inside a single GitHub Actions job
on a 4-hour cron — no persistent state between runs beyond what's in Supabase.
"""

from __future__ import annotations

import logging
import time
from datetime import datetime, timezone

from ai_processor.groq_processor import process_raw_text_to_schema
from database.supabase_client import insert_crisis_report, insert_fact_check
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
# is simply picked up on the next 4-hour cron run.
MAX_ITEMS_PER_RUN = 80


def classify_content_type(item: RawContentItem) -> str:
    """Heuristic: which schema the AI processor should extract for this item.

    Reddit posts are grassroots signals of an ongoing crisis (leaks, protests,
    inaction), so they're routed to CrisisReportSchema. Google News results and
    official Twitter statements usually center on a single checkable claim, so
    they're routed to FactCheckSchema.
    """
    if item.source == "reddit":
        return "crisis_report"
    return "fact_check"


def collect_raw_items() -> list[RawContentItem]:
    items: list[RawContentItem] = []
    items.extend(fetch_all_google_news())
    items.extend(fetch_all_reddit_crises())
    items.extend(fetch_all_twitter())
    logger.info("Collected %d raw items from all fetchers", len(items))
    return items


def process_and_store(item: RawContentItem) -> None:
    content_type = classify_content_type(item)
    text = f"{item.title}\n\n{item.text}".strip()
    if not text:
        return

    result = process_raw_text_to_schema(text, content_type)
    time.sleep(GROQ_CALL_DELAY_SECONDS)

    if result is None:
        return

    if isinstance(result, FactCheckSchema):
        result.source_url = item.url
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
        result.source_url = item.url
        if item.url and not any(e.url == item.url for e in result.evidence_items):
            result.evidence_items.append(
                EvidenceItem(title=item.title, url=item.url, type="LIVE")
            )
        insert_crisis_report(result.model_dump(mode="json"))


def main() -> None:
    items = collect_raw_items()
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
