"""Slow Crisis category 'groundwater': tracks India's annual extractable
groundwater resource total (see fetchers.data_gov_in.fetch_groundwater_records,
a Rajya Sabha reply dataset covering 9 states/UTs, 2020/2022/2023 columns
only - not a true daily feed).

Same core rule as pipeline.slow_crisis_quant: the number and severity verdict
come only from the official dataset's hardcoded arithmetic, never from Groq.

Because the source has just 3 year-columns per state rather than a rolling
daily reading, this module backfills one data point per year (national total
across the 9 covered states/UTs) instead of appending a fresh reading every
run. Re-running is idempotent: it skips any (crisis, recorded_date) pair
that's already stored.
"""

from __future__ import annotations

import asyncio
import logging

from database.supabase_client import (
    fetch_recent_crisis_data_points,
    get_or_create_slow_crisis,
    insert_crisis_data_point,
    update_slow_crisis_description,
    update_slow_crisis_severity,
)
from fetchers.data_gov_in import fetch_groundwater_records

logger = logging.getLogger(__name__)

GROUNDWATER_CRISIS_SLUG = "india-groundwater-extractable-resources"

_DESCRIPTION = (
    "The Central Ground Water Board's annual extractable groundwater "
    "resource estimate measures how much groundwater can be withdrawn "
    "sustainably each year without depleting the aquifer long-term. A "
    "falling total year over year signals shrinking sustainable supply - "
    "from over-extraction for irrigation and drinking water, reduced "
    "recharge due to erratic rainfall, and urbanisation paving over "
    "recharge zones. Unlike a single dry spell, this is a structural, "
    "multi-year depletion trend, which is why it's tracked here as a Slow "
    "Crisis with year-over-year official readings rather than a one-off "
    "drought story."
)
_GENZ_DESCRIPTION = (
    "Groundwater doesn't refill overnight - it's a savings account, and "
    "this tracks whether India's balance is actually growing or quietly "
    "draining. A shrinking number here means less water available next "
    "year for drinking and farming, even if this week's headlines don't "
    "mention it."
)

# Year-over-year percent decline in the national total that counts as a
# genuine worsening/critical trend rather than normal annual fluctuation.
_WORSENING_DECLINE_THRESHOLD = 0.03
_CRITICAL_DECLINE_THRESHOLD = 0.08

_YEAR_FIELDS = {
    2020: "annual_extractable_ground_water_resource_in_bcm___2020",
    2022: "annual_extractable_ground_water_resource_in_bcm___2022",
    2023: "annual_extractable_ground_water_resource_in_bcm___2023",
}


def _parse_numeric(raw) -> float | None:
    if raw is None:
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def _national_totals_by_year(records: list[dict]) -> dict[int, float]:
    """Sums each year's field across every record that has a valid value for
    that year, so one state's missing/malformed field doesn't drop the
    entire year's total to zero."""
    totals: dict[int, float] = {}
    for year, field in _YEAR_FIELDS.items():
        values = [v for v in (_parse_numeric(r.get(field)) for r in records) if v is not None]
        if values:
            totals[year] = sum(values)
    return totals


def _compute_severity(totals_by_year: dict[int, float]) -> str:
    """Pure function, no I/O, no LLM call. Compares the latest year's total
    against the immediately preceding year on record."""
    years = sorted(totals_by_year)
    if len(years) < 2:
        return "stable"

    previous_total = totals_by_year[years[-2]]
    latest_total = totals_by_year[years[-1]]
    if previous_total == 0:
        return "stable"

    change = (latest_total - previous_total) / previous_total
    if change <= -_CRITICAL_DECLINE_THRESHOLD:
        return "critical"
    if change <= -_WORSENING_DECLINE_THRESHOLD:
        return "worsening"
    if change >= _WORSENING_DECLINE_THRESHOLD:
        return "improving"
    return "stable"


async def _run_slow_crisis_groundwater_update_async() -> None:
    records = await fetch_groundwater_records()
    if not records:
        logger.warning("No groundwater records returned from data.gov.in; skipping this run")
        return

    totals_by_year = _national_totals_by_year(records)
    if not totals_by_year:
        logger.warning("Groundwater records had no valid numeric totals for any year; skipping")
        return

    crisis_id = get_or_create_slow_crisis(
        {
            "crisis_slug": GROUNDWATER_CRISIS_SLUG,
            "title": "India's Extractable Groundwater Resources",
            "category": "groundwater",
            "region": "India",
            "description": _DESCRIPTION,
            "genz_description": _GENZ_DESCRIPTION,
            "data_source": "Central Ground Water Board via data.gov.in",
        }
    )
    update_slow_crisis_description(crisis_id, _DESCRIPTION, _GENZ_DESCRIPTION)

    existing_dates = {p["recorded_date"] for p in fetch_recent_crisis_data_points(crisis_id, limit=100)}
    source_url = "https://www.data.gov.in/resource/state-wise-details-annual-extractable-ground-water-resources-form-2020-2023"
    for year in sorted(totals_by_year):
        recorded_date = f"{year}-01-01"
        if recorded_date in existing_dates:
            continue
        insert_crisis_data_point(
            {
                "crisis_id": crisis_id,
                "value": totals_by_year[year],
                "unit": "BCM",
                "recorded_date": recorded_date,
                "source_url": source_url,
            }
        )

    data_points = fetch_recent_crisis_data_points(crisis_id, limit=100)
    severity = _compute_severity({int(p["recorded_date"][:4]): p["value"] for p in data_points})
    update_slow_crisis_severity(crisis_id, severity)
    logger.info(
        "Slow crisis groundwater update: %s totals=%s, severity=%s",
        GROUNDWATER_CRISIS_SLUG,
        totals_by_year,
        severity,
    )


def run_slow_crisis_groundwater_update() -> None:
    """Sync entry point for WEEKLY_JOBS (see main.py)."""
    asyncio.run(_run_slow_crisis_groundwater_update_async())
