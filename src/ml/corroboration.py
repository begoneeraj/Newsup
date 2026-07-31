"""Corroboration scoring: how many independent, credible outlets are also
reporting a given claim, via the project's existing NewsData.io integration
(fetchers.newsdata).
"""

from __future__ import annotations

import asyncio
import logging

from database.publisher_track_record import get_aggregate_fake_rate
from fetchers.newsdata import fetch_all_newsdata

logger = logging.getLogger(__name__)

FAKE_RATE_THRESHOLD = 0.3


def _is_credible_publisher(publisher_name: str) -> bool:
    """True if the publisher has no track record yet (neutral prior) or an
    aggregate fake_rate below FAKE_RATE_THRESHOLD."""
    fake_rate = get_aggregate_fake_rate(publisher_name)
    return fake_rate is None or fake_rate < FAKE_RATE_THRESHOLD


def get_corroboration_score(claim: str) -> float:
    """Searches NewsData.io for `claim` and scores how many DISTINCT, credible
    publishers corroborate it:
      0 sources -> 0.0
      1-2 sources -> 0.5
      3-4 sources -> 0.75
      5+ sources -> 1.0
    """
    try:
        items = asyncio.run(fetch_all_newsdata(queries=[claim]))
    except Exception:
        logger.exception("NewsData search failed for claim=%r; treating as uncorroborated", claim[:200])
        return 0.0

    # Dedup first (same publisher across multiple articles counts once), then
    # apply the credibility filter once per distinct publisher rather than
    # once per article.
    candidate_publishers = {item.outlet_name for item in items if item.outlet_name}
    credible_publishers = {p for p in candidate_publishers if _is_credible_publisher(p)}

    count = len(credible_publishers)
    if count == 0:
        return 0.0
    if count <= 2:
        return 0.5
    if count <= 4:
        return 0.75
    return 1.0
