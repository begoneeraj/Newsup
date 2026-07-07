"""Read-only lookup against the manually curated outlet_credibility table
(supabase/migrations/0006_source_tracking_and_fact_checks_v2.sql).

This module never computes or guesses a score — it only returns what a human
has entered there, citing a named third-party index (Press Council of India,
a named Media Trust Index report, etc.). Outlets with no row simply get None.
"""

from __future__ import annotations

import logging
from typing import Optional

from database.supabase_client import get_client

logger = logging.getLogger(__name__)

_cache: Optional[dict[str, float]] = None


def _load_cache() -> dict[str, float]:
    global _cache
    if _cache is None:
        rows = get_client().table("outlet_credibility").select("outlet_name,credibility_score").execute()
        _cache = {row["outlet_name"]: row["credibility_score"] for row in rows.data}
        logger.info("Loaded %d curated outlet credibility scores", len(_cache))
    return _cache


def lookup_credibility(outlet_name: str) -> Optional[float]:
    """Return the curated credibility_score for this outlet, or None if it
    has no entry in outlet_credibility. Never fabricates a value."""
    return _load_cache().get(outlet_name)
