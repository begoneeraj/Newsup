"""Underreported Topics pipeline. Compares real official/niche source
activity (PRS Legislative bills, sansad.in eLibrary papers, CAG audit
reports) against mainstream news volume (Google News RSS + GDELT DOC 2.0
API, including Hindi/Tamil-scoped GDELT counts) for a fixed catalog of
real civic topics, and surfaces the ones with the largest coverage gap.

This is the implementation of the "Metrics for Undercoverage" step in the
research plan. It establishes the method to quantify how underreported a
topic is, using a "Coverage Gap Score."

The pipeline runs daily and consists of two main parts:
1.  `run_underreported_topics_update`: The quantitative part. For each
    tracked topic, it fetches counts from "niche" sources (e.g.,
    parliamentary records) and "mainstream" sources (e.g., GDELT, Google
    News) and computes a `gap_score`. A high score indicates high niche
    activity and low mainstream coverage.
2.  `run_underreported_topics_narrative_update`: The qualitative part.
    For the most underreported topics, it uses an LLM to generate a
    narrative summary explaining *why* the topic is significant and
    undercovered, based on the data.

The `gap_score` is a simple logarithmic ratio:
`log2((niche_count + 1) / (mainstream_count + 1))`
- Positive score: More niche activity than mainstream (underreported).
- Negative score: More mainstream activity than niche (well-covered).
- Zero score: Balanced coverage or no activity.

This ensures that the score reflects the *ratio* of coverage, not just
absolute counts, which aligns with the research plan's goal of finding a
robust metric.
"""

from __future__ import annotations

import asyncio
import logging
import math
from datetime import date

from ai_processor.groq_processor import process_underreported_topic_narrative
from database.supabase_client import (
    fetch_underreported_topic_points,
    fetch_underreported_topics,
    get_or_create_underreported_topic,
    insert_underreported_topic_narrative,
    insert_underreported_topic_point,
)
from fetchers.cag_reports import fetch_cag_reports_for_topic
from fetchers.gdelt import count_articles as count_gdelt_articles
from fetchers.google_news import count_articles as count_google_news_articles
from fetchers.prs_legislative import fetch_prs_bills_for_topic
from fetchers.sansad_elibrary import fetch_elibrary_records_for_topic
from utils.headline_hash import headline_hash

logger = logging.getLogger(__name__)


def state_centroid(state_name: str) -> tuple[float, float] | None:
    """Returns (lat, lon) for a given Indian state name. Used by the API
    server to place map pins. Hardcoded here to avoid a heavy dependency
    like GeoPandas for a small, fixed list."""
    # fmt: off
    centroids = {
        "Andaman and Nicobar Islands": (11.68, 92.77), "Andhra Pradesh": (15.91, 79.74),
        "Arunachal Pradesh": (28.21, 94.72), "Assam": (26.20, 92.93), "Bihar": (25.09, 85.31),
        "Chandigarh": (30.73, 76.77), "Chhattisgarh": (21.27, 81.86),
        "Dadra and Nagar Haveli and Daman and Diu": (20.18, 73.01), "Delhi": (28.70, 77.10),
        "Goa": (15.29, 74.12), "Gujarat": (22.25, 71.19), "Haryana": (29.05, 76.08),
        "Himachal Pradesh": (31.10, 77.17), "Jammu and Kashmir": (33.77, 76.57),
        "Jharkhand": (23.61, 85.27), "Karnataka": (15.31, 75.71), "Kerala": (10.85, 76.27),
        "Ladakh": (34.15, 77.57), "Lakshadweep": (10.56, 72.64),
        "Madhya Pradesh": (22.97, 78.65), "Maharashtra": (19.75, 75.71),
        "Manipur": (24.66, 93.90), "Meghalaya": (25.46, 91.36), "Mizoram": (23.16, 92.93),
        "Nagaland": (26.15, 94.56), "Odisha": (20.95, 85.09), "Puducherry": (11.94, 79.80),
        "Punjab": (31.14, 75.34), "Rajasthan": (27.02, 74.21), "Sikkim": (27.53, 88.51),
        "Tamil Nadu": (11.12, 78.65), "Telangana": (18.11, 79.01), "Tripura": (23.94, 91.98),
        "Uttar Pradesh": (26.84, 80.94), "Uttarakhand": (30.06, 79.01),
        "West Bengal": (22.98, 87.85),
    }
    # fmt: on
    return centroids.get(state_name.title())


# Each topic is defined with:
# - topic_slug: A unique identifier.
# - title: Human-readable name.
# - category: For grouping in the UI.
# - niche_sources: A list of functions that return a list of items (dict with title, url, state).
#   These are high-signal, low-volume official sources.
# - mainstream_keywords: A GDELT/Google News query string to measure mainstream media attention.
TRACKED_TOPICS = [
    {
        "topic_slug": "environmental-law-and-policy",
        "title": "Environmental Law & Policy",
        "category": "governance",
        "niche_sources": [
            (fetch_prs_bills_for_topic, ["environment", "forest", "wildlife", "pollution"]),
            (fetch_elibrary_records_for_topic, ["environment", "climate change", "pollution control"]),
            (fetch_cag_reports_for_topic, ["environment", "natural resources"]),
        ],
        "mainstream_keywords": '"environmental policy" OR "environmental law" OR "NGT order"',
    },
    {
        "topic_slug": "rural-development-schemes",
        "title": "Rural Development Schemes",
        "category": "rural",
        "niche_sources": [
            (fetch_prs_bills_for_topic, ["rural development", "panchayati raj", "MGNREGA"]),
            (fetch_elibrary_records_for_topic, ["rural development", "agriculture"]),
            (fetch_cag_reports_for_topic, ["rural development"]),
        ],
        "mainstream_keywords": '"rural development" OR "MGNREGA" OR "Pradhan Mantri Gram Sadak Yojana"',
    },
    {
        "topic_slug": "judiciary-and-court-reforms",
        "title": "Judiciary & Court Reforms",
        "category": "governance",
        "niche_sources": [
            (fetch_prs_bills_for_topic, ["judiciary", "court", "judges", "legal reform"]),
            (fetch_elibrary_records_for_topic, ["judicial reform", "court administration"]),
        ],
        "mainstream_keywords": '"judicial reform" OR "court backlog" OR "collegium system"',
    },
    {
        "topic_slug": "data-privacy-and-surveillance",
        "title": "Data Privacy & Surveillance",
        "category": "technology",
        "niche_sources": [
            (fetch_prs_bills_for_topic, ["data protection", "privacy", "surveillance", "telecom"]),
            (fetch_elibrary_records_for_topic, ["data privacy", "cyber security"]),
        ],
        "mainstream_keywords": '"data protection bill" OR "digital privacy" OR "government surveillance"',
    },
    {
        "topic_slug": "labor-rights-informal-economy",
        "title": "Labor Rights & Informal Economy",
        "category": "social",
        "niche_sources": [
            (fetch_prs_bills_for_topic, ["labour code", "minimum wage", "gig workers", "social security"]),
            (fetch_elibrary_records_for_topic, ["unorganised sector", "labour welfare", "employment"]),
            (fetch_cag_reports_for_topic, ["labour", "employment"]),
        ],
        "mainstream_keywords": '"labour rights" OR "informal workers" OR "gig economy protest"',
    },
    {
        "topic_slug": "public-health-infrastructure",
        "title": "Public Health Infrastructure",
        "category": "social",
        "niche_sources": [
            (fetch_prs_bills_for_topic, ["public health", "medical college", "hospital", "disease control"]),
            (fetch_elibrary_records_for_topic, ["health infrastructure", "primary health centre"]),
            (fetch_cag_reports_for_topic, ["national health mission", "health and family welfare"]),
        ],
        "mainstream_keywords": '"public health" OR "hospital capacity" OR "doctor shortage"',
    },
]


def _compute_gap_score(niche_count: int, mainstream_count: int) -> float:
    """Computes the coverage gap score. A higher score means more underreported.
    The formula uses log2 to measure the ratio, which is more sensitive to
    changes at low counts and less sensitive at high counts. Adding 1 to
    counts (Laplace smoothing) avoids division by zero or log(0).
    """
    return math.log2((niche_count + 1) / (mainstream_count + 1))


async def _fetch_niche_sources(
    topic: dict,
) -> tuple[int, list[str], list[dict]]:
    """Fetches all niche sources for a topic concurrently and aggregates results."""
    tasks = []
    for fetcher_func, keywords in topic["niche_sources"]:
        tasks.append(asyncio.to_thread(fetcher_func, keywords))

    results = await asyncio.gather(*tasks)
    all_items = [item for batch in results for item in batch]

    # Deduplicate by URL
    seen_urls = set()
    unique_items = []
    for item in all_items:
        if item["url"] not in seen_urls:
            unique_items.append(item)
            seen_urls.add(item["url"])

    count = len(unique_items)
    states = sorted({item["state"] for item in unique_items if item.get("state")})
    examples = [{"title": item["title"], "url": item["url"]} for item in unique_items[:3]]
    return count, states, examples


async def _fetch_mainstream_sources(
    topic: dict,
) -> tuple[int, int, int, list[dict]]:
    """Fetches all mainstream sources for a topic.

    GDELT enforces a strict per-IP rate limit -- its 429 response body says
    "Please limit requests to one every 5 seconds" -- so the three GDELT
    language queries below must run sequentially, not concurrently. Firing
    them concurrently (the previous behavior) meant all three arrived at
    once and all three got 429'd, every single run, silently collapsing
    en/hi/ta counts to 0 and leaving mainstream_count as just the Google
    News RSS page cap (~100) regardless of the topic's actual coverage --
    which made every tracked topic falsely read as "well covered" no matter
    how underreported it actually was. Google News runs in parallel since
    it's a different host with no such limit.
    """
    keywords = topic["mainstream_keywords"]

    gnews_task = asyncio.to_thread(count_google_news_articles, keywords)

    en_count = await asyncio.to_thread(count_gdelt_articles, keywords, lang="en")
    hi_count = await asyncio.to_thread(count_gdelt_articles, keywords, lang="hi")
    ta_count = await asyncio.to_thread(count_gdelt_articles, keywords, lang="ta")

    gnews_results = await gnews_task

    total_mainstream_count = en_count + hi_count + ta_count + len(gnews_results)
    examples = [{"title": item["title"], "url": item["url"]} for item in gnews_results[:3]]

    return total_mainstream_count, hi_count, ta_count, examples


def run_underreported_topics_update() -> None:
    """The main quantitative pipeline function, run daily."""
    logger.info("Starting underreported topics quantitative update...")
    loop = asyncio.get_event_loop()
    loop.run_until_complete(_run_update_async())
    logger.info("Underreported topics quantitative update complete.")


async def _run_update_async() -> None:
    today = date.today().isoformat()
    for topic in TRACKED_TOPICS:
        try:
            logger.info("Processing topic: %s", topic["title"])

            # Fetch niche and mainstream data concurrently
            niche_task = _fetch_niche_sources(topic)
            mainstream_task = _fetch_mainstream_sources(topic)
            (niche_count, states, niche_examples), (
                mainstream_count,
                hindi_count,
                tamil_count,
                mainstream_examples,
            ) = await asyncio.gather(niche_task, mainstream_task)

            gap_score = _compute_gap_score(niche_count, mainstream_count)

            topic_id = get_or_create_underreported_topic(
                {
                    "topic_slug": topic["topic_slug"],
                    "title": topic["title"],
                    "category": topic["category"],
                    "data_source": "PRS/Sansad/CAG vs GDELT/Google News",
                }
            )

            insert_underreported_topic_point(
                {
                    "topic_id": topic_id,
                    "recorded_date": today,
                    "niche_count": niche_count,
                    "mainstream_count": mainstream_count,
                    "hindi_mainstream_count": hindi_count,
                    "tamil_mainstream_count": tamil_count,
                    "gap_score": gap_score,
                    "states": states,
                    "example_niche_sources": niche_examples,
                    "example_mainstream_sources": mainstream_examples,
                }
            )
            logger.info(
                "Topic '%s' counts: niche=%d, mainstream=%d. Gap score: %.2f",
                topic["title"],
                niche_count,
                mainstream_count,
                gap_score,
            )
        except Exception:
            logger.exception("Failed to process underreported topic: %s", topic["title"])


def run_underreported_topics_narrative_update() -> None:
    """The main qualitative pipeline function, run weekly.
    Implements Phase 3 of the roadmap: generates AI-powered summaries for
    the most underreported topics.
    """
    logger.info("Starting underreported topics narrative update...")
    top_topics = fetch_underreported_topics(limit=5)
    if not top_topics:
        logger.info("No underreported topics with scores found. Skipping narrative update.")
        return

    for topic in top_topics:
        try:
            topic_id = topic["id"]
            points = fetch_underreported_topic_points(topic_id, limit=7)
            if not points:
                continue

            avg_niche = sum(p["niche_count"] for p in points) / len(points)
            avg_mainstream = sum(p["mainstream_count"] for p in points) / len(points)

            data_summary = (
                f"Over the last 7 days, this topic averaged {avg_niche:.1f} daily items from official/niche sources "
                f"(like parliamentary records and audit reports) but only {avg_mainstream:.1f} articles from mainstream media. "
                f"The current gap score is {topic.get('current_gap_score', 0):.2f}."
            )

            result = process_underreported_topic_narrative(topic["title"], data_summary)
            if result is None:
                continue

            # Use a consistent hash to prevent re-inserting the same narrative for the same day.
            narrative_key = f"{topic['topic_slug']}-{date.today().isoformat()}"
            insert_underreported_topic_narrative(
                {
                    "topic_id": topic_id,
                    "narrative_summary": result.narrative_summary,
                    "genz_summary": result.genz_summary,
                    "headline_hash": headline_hash(narrative_key),
                }
            )
            logger.info("Generated narrative for underreported topic: %s", topic["title"])

        except Exception:
            logger.exception("Failed to generate narrative for topic: %s", topic.get("title"))

    logger.info("Underreported topics narrative update complete.")