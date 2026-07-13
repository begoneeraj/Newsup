"""USGS earthquake feed — public GeoJSON, no API key. One of the two
"gov_alerts" sources (see src/fetchers/imd_alerts.py for the other): official
structured data, so main.py::process_gov_alert skips the Groq classification
pass entirely for these items and writes straight to crises/public_events
with verified=True.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Optional

import aiohttp

from models.schemas import RawContentItem

logger = logging.getLogger(__name__)

# "Significant" feed is too sparse for a country-sized area; the M2.5+ past
# week feed gives reasonable coverage without being noisy. See
# https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php for options.
USGS_FEED_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.geojson"

# Rough bounding box covering India (incl. J&K/NE states) — cheap filter so
# a global feed doesn't flood the pipeline with irrelevant quakes.
_INDIA_BBOX = {"min_lat": 6.0, "max_lat": 38.0, "min_lon": 68.0, "max_lon": 98.0}

_TIMEOUT = aiohttp.ClientTimeout(total=15)


def _in_india_bbox(lon: float, lat: float) -> bool:
    return (
        _INDIA_BBOX["min_lon"] <= lon <= _INDIA_BBOX["max_lon"]
        and _INDIA_BBOX["min_lat"] <= lat <= _INDIA_BBOX["max_lat"]
    )


def _parse_feature(feature: dict) -> Optional[RawContentItem]:
    props = feature.get("properties", {})
    geometry = feature.get("geometry", {})
    coords = geometry.get("coordinates") or []
    if len(coords) < 2:
        return None
    lon, lat = coords[0], coords[1]
    if not _in_india_bbox(lon, lat):
        return None

    place = props.get("place", "Unknown location")
    magnitude = props.get("mag")
    if magnitude is None:
        return None

    time_ms = props.get("time")
    published_at = (
        datetime.fromtimestamp(time_ms / 1000, tz=timezone.utc) if time_ms else None
    )

    return RawContentItem(
        source="usgs",
        origin="USGS",
        title=f"M{magnitude:.1f} earthquake - {place}",
        text=props.get("title", "") or place,
        url=props.get("url", ""),
        published_at=published_at,
        outlet_name="USGS",
    )


async def fetch_all_usgs_earthquakes() -> list[RawContentItem]:
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(USGS_FEED_URL, timeout=_TIMEOUT) as response:
                data = await response.json(content_type=None)
    except (aiohttp.ClientError, ValueError) as exc:
        logger.warning("USGS feed fetch failed: %s", exc)
        return []

    items = [_parse_feature(f) for f in data.get("features", [])]
    return [item for item in items if item is not None]
