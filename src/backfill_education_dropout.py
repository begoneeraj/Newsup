"""One-time seed for the education_dropout Slow Crisis category, from the
UDISE+ 2021-22 state/UT school dropout rates published on data.gov.in
(resource 756c8caf-ef26-44d1-8034-c9afd6107aab).

Not a recurring cron job like pipeline.slow_crisis_quant's daily CPCB pull -
this dataset was investigated and confirmed to be a single-year snapshot
(sourced from a Rajya Sabha reply, not a rolling feed with a stable
resource id per period). Wiring it into WEEKLY_JOBS would imply an
automated update cadence that doesn't actually exist, so it's a manual
backfill instead, same shape as backfill_manifesto_promises.py. Re-running
this is safe: get_or_create_slow_crisis is idempotent on crisis_slug, and
this only ever inserts a second crisis_data_points row if the resource's
one "India" reading is re-fetched and re-run (harmless duplicate reading,
same as re-running any other backfill against unchanged source data).

Run manually:

    python src/backfill_education_dropout.py
"""

from __future__ import annotations

import json
import logging
import os
import urllib.parse
import urllib.request

from dotenv import load_dotenv

from database.supabase_client import get_or_create_slow_crisis, insert_crisis_data_point

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("newsup.backfill_education_dropout")

_RESOURCE_ID = "756c8caf-ef26-44d1-8034-c9afd6107aab"
_RESOURCE_URL = f"https://api.data.gov.in/resource/{_RESOURCE_ID}"
_CRISIS_SLUG = "india-secondary-school-dropout-rate"

# UDISE+ 2021-22 report period - this is the academic year the "India" row's
# figure covers, NOT the date this script happens to run on (unlike
# slow_crisis_quant's date.today(), which is legitimate for a same-day live
# AQI reading).
_RECORDED_DATE = "2022-03-31"


def backfill_education_dropout() -> None:
    api_key = os.environ["DATA_GOV_IN_API_KEY"]
    query = urllib.parse.urlencode({"api-key": api_key, "format": "json", "limit": "50"})
    req = urllib.request.Request(f"{_RESOURCE_URL}?{query}", headers={"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.load(resp)
    records = payload.get("records", [])

    india_row = next((r for r in records if r.get("state_ut") == "India"), None)
    if india_row is None:
        logger.error("No 'India' aggregate row found in resource %s; aborting.", _RESOURCE_ID)
        return

    dropout_rate = float(india_row["secondary_drop_out_rate___overall"])

    crisis_id = get_or_create_slow_crisis(
        {
            "crisis_slug": _CRISIS_SLUG,
            "title": "India Secondary School Dropout Rate",
            "category": "education_dropout",
            "region": "India",
            "description": (
                "Tracks the national secondary-school dropout rate from UDISE+ "
                "(Unified District Information System for Education Plus), the "
                "Ministry of Education's official school data system."
            ),
            "data_source": "UDISE+ 2021-22 via data.gov.in",
        }
    )

    insert_crisis_data_point(
        {
            "crisis_id": crisis_id,
            "value": dropout_rate,
            "unit": "%",
            "recorded_date": _RECORDED_DATE,
            "source_url": f"https://www.data.gov.in/resource/{_RESOURCE_ID}",
            "note": "UDISE+ 2021-22 academic year, national aggregate (single annual snapshot, not a live feed).",
        }
    )
    logger.info("Seeded %s: %.1f%% (recorded_date=%s)", _CRISIS_SLUG, dropout_rate, _RECORDED_DATE)


if __name__ == "__main__":
    backfill_education_dropout()
