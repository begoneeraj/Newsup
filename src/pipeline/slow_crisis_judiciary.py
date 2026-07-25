"""Slow Crisis category 'judiciary_delay': tracks the total number of cases
pending across the Supreme Court, High Courts, and District/Subordinate
Courts nationally.

Unlike air_pollution/groundwater there is no scriptable NJDG (National
Judicial Data Grid) API - data.gov.in's own catalog search returned 404/403
for every NJDG resource tried, and njdg.ecourts.gov.in isn't a machine-
readable endpoint either. So this module reads locally-committed CSV
snapshots (see data/court_cases/) manually pulled from NJDG at specific
"as on" dates, rather than fetching live like fetchers.data_gov_in does.
Adding a new reading later means dropping in a new dated CSV and adding one
line to _SNAPSHOTS below - there's no code change needed beyond that.

Same core rule as pipeline.slow_crisis_quant: the number and severity verdict
come only from the official snapshot's hardcoded arithmetic, never from Groq.
"""

from __future__ import annotations

import csv
import logging
from pathlib import Path

from database.supabase_client import (
    fetch_recent_crisis_data_points,
    get_or_create_slow_crisis,
    insert_crisis_data_point,
    update_slow_crisis_description,
    update_slow_crisis_severity,
)

logger = logging.getLogger(__name__)

JUDICIARY_CRISIS_SLUG = "india-court-case-backlog"

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "court_cases"

# (recorded_date, csv path, pending-cases column name, source note). Each row
# in these CSVs is one court tier (Supreme Court / High Courts / District &
# Subordinate Courts); the tracked number is the national total across all
# three. The 2016/2022 comparison file has one row per tier with both years
# as separate columns, so it contributes two snapshots.
_SNAPSHOTS = [
    ("2016-01-01", _DATA_DIR / "court_cases_2016_2022.csv", "Cases pending in 2016"),
    ("2022-07-29", _DATA_DIR / "court_cases_2016_2022.csv", "Cases pending in 2022"),
    ("2024-11-30", _DATA_DIR / "njdg_pending_2024-11-30.csv", "Pending cases"),
    ("2025-03-06", _DATA_DIR / "njdg_pending_2025-03-06.csv", "Number of Pending Cases"),
]

_SOURCE_URL = "https://njdg.ecourts.gov.in/"

_DESCRIPTION = (
    "India's courts - Supreme Court, High Courts, and District/Subordinate "
    "Courts - carry a backlog of tens of millions of pending cases, per the "
    "National Judicial Data Grid (NJDG). A case pending for years means "
    "delayed justice for everyone involved: undertrial prisoners held "
    "without conviction, civil disputes left unresolved, and victims "
    "waiting years for a hearing. Unlike a single high-profile verdict, "
    "this is a structural, decades-in-the-making backlog, which is why "
    "it's tracked here as a Slow Crisis with periodic official snapshots "
    "rather than as a one-off court story."
)
_GENZ_DESCRIPTION = (
    "\"Justice delayed is justice denied\" isn't just a saying here - it's "
    "tens of millions of real cases sitting in a queue, some for over a "
    "decade. This tracks whether that backlog is actually shrinking or "
    "just quietly growing every year, using NJDG's own published numbers."
)

# Year-over-year percent growth in the national total pending-case count
# that counts as a genuine worsening/critical trend rather than routine
# year-to-year fluctuation. Growth (not decline) is the bad direction here,
# opposite of pipeline.slow_crisis_groundwater's decline-is-bad framing.
_WORSENING_GROWTH_THRESHOLD = 0.02
_CRITICAL_GROWTH_THRESHOLD = 0.06


def _parse_count(raw: str) -> int:
    return int(raw.strip().replace(",", ""))


def _total_pending(csv_path: Path, column: str) -> float | None:
    if not csv_path.exists():
        logger.warning("Court case snapshot file missing: %s", csv_path)
        return None
    with csv_path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    values = [v for v in (_parse_count(row[column]) for row in rows if row.get(column)) if v is not None]
    if not values:
        return None
    return float(sum(values))


def _compute_severity(totals_by_date: dict[str, float]) -> str:
    """Pure function, no I/O, no LLM call. Compares the latest snapshot
    against the immediately preceding one on record, by date order."""
    dates = sorted(totals_by_date)
    if len(dates) < 2:
        return "stable"

    previous_total = totals_by_date[dates[-2]]
    latest_total = totals_by_date[dates[-1]]
    if previous_total == 0:
        return "stable"

    change = (latest_total - previous_total) / previous_total
    if change >= _CRITICAL_GROWTH_THRESHOLD:
        return "critical"
    if change >= _WORSENING_GROWTH_THRESHOLD:
        return "worsening"
    if change <= -_WORSENING_GROWTH_THRESHOLD:
        return "improving"
    return "stable"


def run_slow_crisis_judiciary_update() -> None:
    """Sync entry point for WEEKLY_JOBS (see main.py). No async/network I/O
    needed here (unlike slow_crisis_quant/groundwater) since the source is
    local CSV snapshots, not a live fetch."""
    crisis_id = get_or_create_slow_crisis(
        {
            "crisis_slug": JUDICIARY_CRISIS_SLUG,
            "title": "India's Court Case Backlog",
            "category": "judiciary_delay",
            "region": "India",
            "description": _DESCRIPTION,
            "genz_description": _GENZ_DESCRIPTION,
            "data_source": "National Judicial Data Grid (NJDG)",
        }
    )
    update_slow_crisis_description(crisis_id, _DESCRIPTION, _GENZ_DESCRIPTION)

    existing_dates = {p["recorded_date"] for p in fetch_recent_crisis_data_points(crisis_id, limit=100)}
    for recorded_date, csv_path, column in _SNAPSHOTS:
        if recorded_date in existing_dates:
            continue
        total = _total_pending(csv_path, column)
        if total is None:
            logger.warning("Skipping unreadable court case snapshot %s (%s)", csv_path, column)
            continue
        insert_crisis_data_point(
            {
                "crisis_id": crisis_id,
                "value": total,
                "unit": "pending cases",
                "recorded_date": recorded_date,
                "source_url": _SOURCE_URL,
            }
        )

    data_points = fetch_recent_crisis_data_points(crisis_id, limit=100)
    severity = _compute_severity({p["recorded_date"]: p["value"] for p in data_points})
    update_slow_crisis_severity(crisis_id, severity)
    logger.info("Slow crisis judiciary update: %s severity=%s", JUDICIARY_CRISIS_SLUG, severity)
