"""Track 1 (quantitative) of the Slow Crises module: pulls the latest
official reading for a tracked crisis, inserts it into crisis_data_points,
and computes current_severity with plain arithmetic against hardcoded
thresholds.

THE CORE RULE FOR THIS WHOLE MODULE: the number and the severity verdict
must never come from Groq - only from the official dataset and this
file's hardcoded threshold logic. Groq's only role anywhere in the Slow
Crises feature is narrative/context (see pipeline.slow_crisis_narrative,
Track 2) - it is never asked to estimate a value or judge severity. Do not
"helpfully" route _compute_severity through an LLM call later; that would
undermine the entire point of this module, which exists specifically so
citizens can trust a number came from CPCB/CGWB/NJDG/etc., not from a
model's guess.

Scoped to one category this session: air pollution, tracked via Delhi
PM2.5 (see fetchers.data_gov_in - CPCB's data mirrored on data.gov.in,
since cpcb.nic.in itself is unreachable from this environment). PM2.5 is
tracked directly rather than a composite AQI, since computing a true
composite AQI needs CPCB's own per-pollutant sub-index breakpoints and a
max-across-pollutants step that's out of scope for this first category.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import date

from database.supabase_client import (
    fetch_recent_crisis_data_points,
    get_or_create_slow_crisis,
    insert_crisis_data_point,
    update_slow_crisis_description,
    update_slow_crisis_severity,
)
from fetchers.data_gov_in import fetch_aqi_records

logger = logging.getLogger(__name__)

DELHI_PM25_CRISIS_SLUG = "delhi-air-quality-pm25"

# Static reference copy, not a per-run Groq call - this explains the
# *general* problem (what PM2.5 is, why it's tracked, who it hits hardest),
# not a specific data verdict, so hand-written prose is appropriate here the
# same way it's inappropriate for _compute_severity's number (see this
# module's top-of-file docstring on why the number/severity can never come
# from Groq - context/background prose is a different thing, same
# distinction pipeline.slow_crisis_narrative draws for Track 2 narratives).
_DESCRIPTION = (
    "Delhi's PM2.5 (fine particulate matter under 2.5 micrometres) routinely "
    "exceeds India's National Ambient Air Quality Standard, and WHO's "
    "guideline, by several multiples - driven by vehicle emissions, "
    "construction dust, industrial activity, and seasonal stubble burning in "
    "neighbouring states. Long-term exposure is linked to reduced lung "
    "function, aggravated asthma, cardiovascular disease, and reduced life "
    "expectancy, with children and students among the most exposed given "
    "time spent outdoors commuting to school and college. Unlike a single "
    "pollution event, this is a structural, year-round health burden that "
    "outlasts any one news cycle - which is why it's tracked here as a Slow "
    "Crisis, with a daily official reading, rather than as a one-off story."
)
_GENZ_DESCRIPTION = (
    "Delhi's air is bad often enough that it's stopped being 'news' and just "
    "became the baseline. PM2.5 here regularly blows past what's officially "
    "considered safe, and the people breathing it hardest every single day "
    "are students walking to school or waiting for a bus, not adults in "
    "sealed offices. That's the actual crisis: not one bad air day, but "
    "hundreds of them a year, tracked here with a real daily number instead "
    "of just showing up whenever it's bad enough to trend."
)

# CPCB's own published 24h PM2.5 AQI sub-index breakpoint for "Severe" -
# crossing this crosses into "critical" regardless of trend direction.
PM25_CRITICAL_THRESHOLD = 250.0

# How many recent readings make up each side of the trend comparison, and
# the minimum percent change to call it worsening/improving rather than
# noise-level "stable".
_TREND_WINDOW = 3
_TREND_CHANGE_THRESHOLD = 0.10


def _average(values: list[float]) -> float:
    return sum(values) / len(values)


def _compute_severity(data_points: list[dict]) -> str:
    """Pure function, no I/O, no LLM call. data_points must be sorted
    oldest-first by recorded_date; each dict has a numeric 'value' key.
    Returns one of SlowCrisisSeverity's values (stable/worsening/improving/critical)."""
    if not data_points:
        return "stable"

    latest_value = data_points[-1]["value"]
    if latest_value >= PM25_CRITICAL_THRESHOLD:
        return "critical"

    # Require a full 2 * _TREND_WINDOW readings so recent_window and
    # previous_window are always equal-sized (3-vs-3, not e.g. 3-vs-1) -
    # otherwise a single old outlier can dominate a too-small previous_window
    # and flip severity off noise rather than a genuine trend.
    if len(data_points) < 2 * _TREND_WINDOW:
        return "stable"

    recent_window = [p["value"] for p in data_points[-_TREND_WINDOW:]]
    previous_window = [p["value"] for p in data_points[-(2 * _TREND_WINDOW):-_TREND_WINDOW]]

    recent_avg = _average(recent_window)
    previous_avg = _average(previous_window)
    if previous_avg == 0:
        return "stable"

    change = (recent_avg - previous_avg) / previous_avg
    if change >= _TREND_CHANGE_THRESHOLD:
        return "worsening"
    if change <= -_TREND_CHANGE_THRESHOLD:
        return "improving"
    return "stable"


def _parse_numeric(raw: str | None) -> float | None:
    if raw is None:
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


async def _latest_delhi_pm25_value() -> tuple[float, str] | None:
    """Returns (averaged PM2.5 value across reporting stations, source_url)
    for today's reading, or None if no valid PM2.5 records were returned."""
    records = await fetch_aqi_records(city="Delhi", limit=200)
    pm25_values = [
        v for v in (_parse_numeric(r.get("avg_value")) for r in records if r.get("pollutant_id") == "PM2.5") if v is not None
    ]
    if not pm25_values:
        logger.warning("No valid Delhi PM2.5 readings in this data.gov.in response")
        return None
    return _average(pm25_values), "https://www.data.gov.in/resource/real-time-air-quality-index-various-locations"


async def _run_slow_crisis_quant_update_async() -> None:
    reading = await _latest_delhi_pm25_value()
    if reading is None:
        return
    value, source_url = reading

    crisis_id = get_or_create_slow_crisis(
        {
            "crisis_slug": DELHI_PM25_CRISIS_SLUG,
            "title": "Delhi Air Quality (PM2.5)",
            "category": "air_pollution",
            "region": "Delhi",
            "description": _DESCRIPTION,
            "genz_description": _GENZ_DESCRIPTION,
            "data_source": "CPCB via data.gov.in",
        }
    )
    # get_or_create_slow_crisis never updates descriptive fields on a row
    # that already exists (by design - see its docstring), so the row
    # created before this module had real description copy needs an
    # explicit, separate refresh here. Idempotent/cheap, safe daily.
    update_slow_crisis_description(crisis_id, _DESCRIPTION, _GENZ_DESCRIPTION)

    insert_crisis_data_point(
        {
            "crisis_id": crisis_id,
            "value": value,
            "unit": "ug/m3",
            "recorded_date": date.today().isoformat(),
            "source_url": source_url,
        }
    )

    data_points = fetch_recent_crisis_data_points(crisis_id, limit=30)
    severity = _compute_severity(data_points)
    update_slow_crisis_severity(crisis_id, severity)
    logger.info("Slow crisis quant update: %s = %.1f ug/m3, severity=%s", DELHI_PM25_CRISIS_SLUG, value, severity)


def run_slow_crisis_quant_update() -> None:
    """Sync entry point for WEEKLY_JOBS (see main.py) - main()'s dispatch
    calls WEEKLY_JOBS[job_name]() synchronously (same as
    run_promise_reverification), so this wraps the async data.gov.in fetch
    in asyncio.run() rather than requiring main() to special-case async
    jobs. Scoped to the one Delhi PM2.5 category this session - replicate
    _latest_delhi_pm25_value's shape for each additional category once its
    data source is verified live."""
    asyncio.run(_run_slow_crisis_quant_update_async())
