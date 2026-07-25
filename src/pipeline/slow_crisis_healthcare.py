"""Slow Crisis category 'healthcare_capacity': tracks average reported bed
capacity per hospital nationally, from the National Hospital Directory (see
data/healthcare/national_hospital_directory.csv - ~30k hospitals, with geo
coordinates and a Total_Num_Beds column).

No live API exists for this directory (it's a bulk export, not a
data.gov.in resource with a resource id), so like
pipeline.slow_crisis_judiciary this reads a locally-committed CSV rather
than fetching over the network. Re-running with the same file produces the
same value, which is expected - the tracked number only changes once a
refreshed export replaces this file.

Same core rule as pipeline.slow_crisis_quant: the number and severity verdict
come only from the directory's own hardcoded arithmetic, never from Groq. No
absolute "critical" bed-count threshold is applied (unlike PM2.5's
CPCB-defined breakpoint) because no official minimum-beds-per-hospital
standard exists to cite - severity here is trend-only, comparing the latest
snapshot against the previous one on record.

Total_Num_Beds of 0 is treated as "not reported" rather than "zero beds" -
this directory uses "0" as a placeholder for every unpopulated field (phone
numbers, emails, bed counts alike), confirmed by inspecting sample rows
where an entire hospital's optional fields are all literal "0".
"""

from __future__ import annotations

import csv
import logging
from datetime import date
from pathlib import Path

from database.supabase_client import (
    fetch_recent_crisis_data_points,
    get_or_create_slow_crisis,
    insert_crisis_data_point,
    update_slow_crisis_description,
    update_slow_crisis_severity,
)

logger = logging.getLogger(__name__)

HEALTHCARE_CRISIS_SLUG = "india-hospital-bed-capacity"

_CSV_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "healthcare" / "national_hospital_directory.csv"
_SOURCE_URL = "https://www.data.gov.in/catalog/national-hospital-directory"

_DESCRIPTION = (
    "The National Hospital Directory lists tens of thousands of hospitals "
    "nationwide with their reported bed capacity. Average beds per "
    "hospital is a rough proxy for how much a typical facility can actually "
    "handle - a falling average suggests capacity is being spread thinner "
    "as more small facilities open relative to well-equipped ones, or that "
    "reporting quality is declining. Unlike a single hospital's crisis, "
    "this is a structural, nationwide capacity question, which is why it's "
    "tracked here as a Slow Crisis with periodic official directory "
    "snapshots rather than as a one-off hospital story."
)
_GENZ_DESCRIPTION = (
    "A hospital existing on paper isn't the same as a hospital that can "
    "actually treat you - bed count is the difference. This tracks the "
    "national average so a wave of tiny, under-equipped facilities opening "
    "up doesn't get mistaken for healthcare access actually improving."
)

# Percent change in average beds/hospital vs. the previous snapshot that
# counts as a genuine worsening/improving trend rather than noise.
_TREND_CHANGE_THRESHOLD = 0.05

# India's largest hospitals run a few thousand beds at most - a handful of
# rows in this directory have obvious data-entry garbage in Total_Num_Beds
# (10-digit values that are clearly a misplaced phone number, not a bed
# count, e.g. 9686825522). Anything above this cap is excluded as bad data
# rather than treated as a real reading, the same way 0 is excluded as
# "not reported".
_MAX_PLAUSIBLE_BEDS = 10000


def _aggregate_bed_capacity(csv_path: Path) -> tuple[float, int] | None:
    """Returns (average beds per hospital, hospitals with beds reported),
    counting only rows where Total_Num_Beds is a positive integer (see
    module docstring on why 0 means "not reported" here, not "zero beds")."""
    if not csv_path.exists():
        logger.warning("Hospital directory file missing: %s", csv_path)
        return None

    total_beds = 0
    reporting_count = 0
    with csv_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            raw = row.get("Total_Num_Beds")
            if not raw:
                continue
            try:
                beds = int(raw.strip())
            except ValueError:
                continue
            if 0 < beds <= _MAX_PLAUSIBLE_BEDS:
                total_beds += beds
                reporting_count += 1

    if reporting_count == 0:
        return None
    return total_beds / reporting_count, reporting_count


def _compute_severity(data_points: list[dict]) -> str:
    """Pure function, no I/O, no LLM call. data_points must be sorted
    oldest-first by recorded_date. A falling average beds/hospital is the
    bad direction here."""
    if len(data_points) < 2:
        return "stable"

    previous_value = data_points[-2]["value"]
    latest_value = data_points[-1]["value"]
    if previous_value == 0:
        return "stable"

    change = (latest_value - previous_value) / previous_value
    if change <= -_TREND_CHANGE_THRESHOLD:
        return "worsening"
    if change >= _TREND_CHANGE_THRESHOLD:
        return "improving"
    return "stable"


def run_slow_crisis_healthcare_update() -> None:
    """Sync entry point for WEEKLY_JOBS (see main.py). No async/network I/O
    needed here (unlike slow_crisis_quant/groundwater) since the source is
    a local CSV directory export, not a live fetch."""
    aggregate = _aggregate_bed_capacity(_CSV_PATH)
    if aggregate is None:
        logger.warning("No hospitals with reported bed capacity found; skipping this run")
        return
    average_beds, reporting_count = aggregate

    crisis_id = get_or_create_slow_crisis(
        {
            "crisis_slug": HEALTHCARE_CRISIS_SLUG,
            "title": "India's Hospital Bed Capacity",
            "category": "healthcare_capacity",
            "region": "India",
            "description": _DESCRIPTION,
            "genz_description": _GENZ_DESCRIPTION,
            "data_source": "National Hospital Directory",
        }
    )
    update_slow_crisis_description(crisis_id, _DESCRIPTION, _GENZ_DESCRIPTION)

    recorded_date = date.today().isoformat()
    existing_dates = {p["recorded_date"] for p in fetch_recent_crisis_data_points(crisis_id, limit=100)}
    if recorded_date not in existing_dates:
        insert_crisis_data_point(
            {
                "crisis_id": crisis_id,
                "value": average_beds,
                "unit": "avg beds/hospital",
                "recorded_date": recorded_date,
                "source_url": _SOURCE_URL,
            }
        )

    data_points = fetch_recent_crisis_data_points(crisis_id, limit=100)
    severity = _compute_severity(data_points)
    update_slow_crisis_severity(crisis_id, severity)
    logger.info(
        "Slow crisis healthcare update: %s avg_beds=%.1f (n=%d hospitals reporting), severity=%s",
        HEALTHCARE_CRISIS_SLUG,
        average_beds,
        reporting_count,
        severity,
    )
