"""Thin JSON client for the data.gov.in Open Government Data (OGD) REST API
(api.data.gov.in/resource/<uuid>). Confirmed live via manual query before
writing this, including the specific resource used by Data Stories/Slow
Crises Track 1: CPCB's "Real time Air Quality Index from various locations"
(resource 3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69), which mirrors CPCB data
onto a reachable host after cpcb.nic.in itself proved unreachable from this
environment.

Each record is one (station, pollutant) reading - country, state, city,
station, last_update, latitude, longitude, pollutant_id, min_value,
max_value, avg_value - NOT a precomputed composite AQI despite the
resource's title. Composite AQI needs per-pollutant sub-index breakpoints
and a max-across-pollutants step CPCB itself defines; out of scope for this
first Slow Crisis category, so pipeline.slow_crisis_quant tracks one
pollutant (PM2.5) directly instead of pretending to compute a composite AQI.

Shared by src/pipeline/slow_crisis_quant.py (Track 1) and the AQI-based Data
Story generator - both need the same raw records, just different
downstream treatment (severity thresholds vs. a narrative write-up).
"""

from __future__ import annotations

import logging
import os

import aiohttp

logger = logging.getLogger(__name__)

_API_BASE_URL = "https://api.data.gov.in/resource/{resource_id}"
_TIMEOUT = aiohttp.ClientTimeout(total=20)
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; NewsUpBot/1.0)"}

AQI_RESOURCE_ID = "3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69"


def _api_key() -> str:
    # Register your own free key at data.gov.in — the shared demo key
    # (published in data.gov.in's own API docs) is rate-limited/shared and
    # not meant for production use.
    return os.environ["DATA_GOV_IN_API_KEY"]


async def fetch_resource_records(resource_id: str, *, limit: int = 100, filters: dict | None = None) -> list[dict]:
    """Fetches up to `limit` records from a data.gov.in resource. `filters`
    maps field name -> value, passed as the API's `filters[field]=value`
    query params (e.g. {"city": "Delhi"})."""
    try:
        api_key = _api_key()
    except KeyError:
        logger.warning("DATA_GOV_IN_API_KEY not set; skipping data.gov.in fetch for resource=%s", resource_id)
        return []

    params = {"api-key": api_key, "format": "json", "limit": str(limit)}
    for field, value in (filters or {}).items():
        params[f"filters[{field}]"] = value

    url = _API_BASE_URL.format(resource_id=resource_id)
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, params=params, timeout=_TIMEOUT, headers=_HEADERS) as response:
                if response.status != 200:
                    logger.warning("data.gov.in fetch got HTTP %d for resource=%s", response.status, resource_id)
                    return []
                payload = await response.json(content_type=None)
    except aiohttp.ClientError as exc:
        logger.warning("data.gov.in fetch failed for resource=%s: %s", resource_id, exc)
        return []

    return payload.get("records", [])


async def fetch_aqi_records(*, city: str | None = None, limit: int = 200) -> list[dict]:
    filters = {"city": city} if city else None
    return await fetch_resource_records(AQI_RESOURCE_ID, limit=limit, filters=filters)
