"""Data Stories module, scoped to one generator this session: turns the
accumulated Delhi PM2.5 readings (see pipeline.slow_crisis_quant, which
already writes to crisis_data_points on its own daily job) into a narrative
"data story" - what changed and why it matters, both tones.

Reuses the same crisis_data_points history Slow Crises Track 1 already
builds rather than maintaining a second copy of the same numbers - Data
Stories and Slow Crises are different presentations of the same
official-dataset trail, not two independent data pipelines. All numeric
work (latest value, percent change, min/max) happens in code before Groq
ever sees the data; Groq only writes the narrative framing around numbers
it's given, never computes or estimates one itself (see
groq_processor._DATA_STORY_SYSTEM_PROMPT).
"""

from __future__ import annotations

import logging
from datetime import date

from ai_processor.groq_processor import process_data_story
from database.supabase_client import fetch_recent_crisis_data_points, get_or_create_slow_crisis, insert_data_story
from pipeline.slow_crisis_quant import DELHI_PM25_CRISIS_SLUG
from utils.headline_hash import headline_hash

logger = logging.getLogger(__name__)

_TREND_DAYS = 30


def _build_numbers_summary(data_points: list[dict]) -> tuple[str, str, list[dict]]:
    """Returns (numbers_summary_for_groq, headline_stat, chart_data)."""
    latest = data_points[-1]
    latest_value = latest["value"]
    chart_data = [{"date": p["recorded_date"], "value": p["value"]} for p in data_points]

    if len(data_points) > 1:
        earliest = data_points[0]
        change_pct = ((latest_value - earliest["value"]) / earliest["value"] * 100) if earliest["value"] else 0.0
        summary = (
            f"Delhi's average PM2.5 level on {latest['recorded_date']} is {latest_value:.0f} ug/m3. "
            f"On {earliest['recorded_date']} ({len(data_points)} readings ago) it was {earliest['value']:.0f} ug/m3, "
            f"a change of {change_pct:+.0f}%."
        )
    else:
        summary = f"Delhi's average PM2.5 level on {latest['recorded_date']} is {latest_value:.0f} ug/m3 (first recorded reading)."

    headline_stat = f"{latest_value:.0f} ug/m3 PM2.5"
    return summary, headline_stat, chart_data


def run_data_story_aqi_update() -> None:
    """Entry point for the monthly Data Stories job (see
    .github/workflows/data_stories_cron.yml,
    `python src/main.py --sources data_stories_aqi`)."""
    crisis_id = get_or_create_slow_crisis(
        {
            "crisis_slug": DELHI_PM25_CRISIS_SLUG,
            "title": "Delhi Air Quality (PM2.5)",
            "category": "air_pollution",
            "region": "Delhi",
            "description": "Tracks Delhi's daily average PM2.5 concentration against CPCB's severe-pollution threshold.",
            "data_source": "CPCB via data.gov.in",
        }
    )
    data_points = fetch_recent_crisis_data_points(crisis_id, limit=_TREND_DAYS)
    if not data_points:
        logger.info("No crisis_data_points yet for %s; skipping data story", DELHI_PM25_CRISIS_SLUG)
        return

    numbers_summary, headline_stat, chart_data = _build_numbers_summary(data_points)
    result = process_data_story("CPCB Real-Time AQI (via data.gov.in)", numbers_summary)
    if result is None:
        return

    story_key = f"{DELHI_PM25_CRISIS_SLUG}-{date.today().isoformat()}"
    insert_data_story(
        {
            "slug": story_key,
            "title": result.title,
            "genz_title": result.genz_title,
            "dataset_source": "CPCB Real-Time AQI (via data.gov.in)",
            "headline_stat": headline_stat,
            "narrative_summary": result.narrative_summary,
            "genz_summary": result.genz_summary,
            "chart_data": chart_data,
            "headline_hash": headline_hash(story_key),
        }
    )
    logger.info("Inserted AQI data story: %s", result.title)
