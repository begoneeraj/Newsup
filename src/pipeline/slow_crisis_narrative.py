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

# SLOW_CRISIS_KEYWORDS (main.py) is scoped to air_pollution this session -
# the only category with a live Track 1 quantitative source (see
# pipeline.slow_crisis_quant's docstring) - so every article reaching this
# module already matched an air-pollution keyword before Groq or fuzzy
# matching ever sees it. Empirically checked against real headlines
# ("Delhi AQI hits 85-day high...", "Delhi's AQI Touches 261...") that the
# codebase's own STRICT_TITLE_MATCH_THRESHOLD was silently dropping: catalog
# titles like "Delhi Air Quality (PM2.5)" share little literal wording with
# real AQI headlines, so the fuzzy gate was rejecting the large majority of
# genuine matches. Update this alongside SLOW_CRISIS_KEYWORDS once a second
# category gets a live quant source.
_SCOPED_CATEGORY = "air_pollution"


def _best_matching_crisis(article_title: str, candidates: list[dict]) -> dict | None:
    # Candidates here are every tracked slow crisis, not a pre-narrowed
    # same-event set - see STRICT_TITLE_MATCH_THRESHOLD's docstring for why
    # DEDUP_TITLE_THRESHOLD is unsafe for this call site. Narrow to the
    # keyword list's own category first: the fuzzy title match below exists
    # to disambiguate between *multiple* candidates, not to gate a single
    # unambiguous one - with exactly one air_pollution crisis tracked today,
    # keyword routing has already confirmed the topic, so a single same-
    # category candidate is used directly. Falls back to every candidate if
    # somehow none match the scoped category, and still runs the fuzzy gate
    # whenever the narrowed set has more than one candidate, so this stays
    # safe once a second same-category crisis is added.
    same_category = [c for c in candidates if c.get("category") == _SCOPED_CATEGORY] or candidates
    if len(same_category) == 1:
        return same_category[0]

    best: dict | None = None
    best_score = 0.0
    for candidate in same_category:
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
