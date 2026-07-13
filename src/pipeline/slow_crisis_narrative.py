"""Track 2 (narrative) of the Slow Crises module: matches an incoming news
article against tracked slow_crises by fuzzy title match, then records it
as a crisis_narrative_updates row via a Groq-generated narrative - context
only, never a data point or severity verdict (see pipeline.slow_crisis_quant
for why that distinction is trust-critical to this whole module).

Mirrors pipeline.promise_evidence's shape closely: fetch candidates,
fuzzy-match, one Groq call, insert a child row.
"""

from __future__ import annotations

import logging

from ai_processor.groq_processor import process_slow_crisis_narrative
from database.supabase_client import fetch_all_slow_crises, insert_crisis_narrative_update
from models.schemas import RawContentItem
from utils.fuzzy_match import STRICT_TITLE_MATCH_THRESHOLD, title_similarity
from utils.headline_hash import headline_hash

logger = logging.getLogger(__name__)


def _best_matching_crisis(article_title: str, candidates: list[dict]) -> dict | None:
    # Candidates here are every tracked slow crisis, not a pre-narrowed
    # same-event set - see STRICT_TITLE_MATCH_THRESHOLD's docstring for why
    # DEDUP_TITLE_THRESHOLD is unsafe for this call site.
    best: dict | None = None
    best_score = 0.0
    for candidate in candidates:
        score = title_similarity(article_title, candidate["title"])
        if score > best_score:
            best_score = score
            best = candidate
    if best is not None and best_score >= STRICT_TITLE_MATCH_THRESHOLD:
        return best
    return None


def process_slow_crisis_narrative_item(item: RawContentItem, text: str) -> None:
    """Entry point called from main.process_expansion_module() when
    module == "slow_crisis". Skips Groq entirely if the article doesn't
    fuzzy-match any tracked crisis."""
    candidates = fetch_all_slow_crises()
    if not candidates:
        return

    match = _best_matching_crisis(item.title, candidates)
    if match is None:
        return

    result = process_slow_crisis_narrative(match["title"], item.title, text)
    if result is None:
        return

    insert_crisis_narrative_update(
        {
            "crisis_id": match["id"],
            "narrative": result.narrative,
            "genz_narrative": result.genz_narrative,
            "source_url": item.url,
            "headline_hash": headline_hash(item.title),
        }
    )
    logger.info("Recorded slow crisis narrative update for %s", match["title"])
