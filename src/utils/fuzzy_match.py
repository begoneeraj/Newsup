"""Fuzzy title matching — the near-duplicate dedup layer that sits above the
exact-match headline_hash check in headline_hash.py. Catches the case that
exact hashing can't: two articles about the same real-world event with
genuinely different wording (e.g. "Heavy rain causes floods in UP" vs "UP
flooding hits Lucknow amid heavy rains"), which fact_checks/crisis_reports
already handle via pgvector embeddings but crises/public_events did not.

Uses stdlib difflib rather than embeddings — small, fast, no extra
infrastructure, and the candidate sets it's run against (see
supabase_client.find_mergeable_public_event) are already narrowed by
event_type + place + a time window, so a cheap string-similarity ratio is
enough to separate "same event" from "coincidentally similar wording".
"""

from __future__ import annotations

from difflib import SequenceMatcher

from utils.headline_hash import normalize_headline

# Below this, two titles are treated as different events even if they share
# some words. Deliberately permissive: callers only run this over a
# candidate set already narrowed by event_type + place + a short time
# window (see supabase_client.find_recent_public_events /
# find_recent_crisis_titles), so the base rate of two *unrelated* events
# sharing that much context is already low — the risk this threshold is
# guarding against is under-merging (duplicate cards), not over-merging.
DEDUP_TITLE_THRESHOLD = 0.3

# For callers matching against a candidate set that is NOT pre-narrowed
# (pipeline.slow_crisis_narrative and pipeline.promise_evidence run this
# against every tracked crisis/promise, not a same-event/same-window subset)
# DEDUP_TITLE_THRESHOLD is unsafe: short catalog-style titles like "Delhi Air
# Quality (PM2.5)" or "Mumbai Metro Line 3" share a place name or institution
# with plenty of unrelated headlines, and empirically a genuine match can
# score *lower* than an unrelated false positive (verified: "Delhi Air
# Quality (PM2.5)" vs an unrelated "Mumbai...ridership" headline scores
# higher than the same crisis vs a real PM2.5 news update). No threshold on
# this metric cleanly separates true/false positives for these callers -
# this raised bar trades recall for precision (a missed narrative/evidence
# update is far cheaper than one wrongly attributed to the wrong crisis or
# promise). The real fix is an embedding-based match (see
# pipeline.promise_evidence's module docstring); this is a stopgap.
STRICT_TITLE_MATCH_THRESHOLD = 0.45

# Suffixes stripped before comparing tokens so "flood"/"floods"/"flooding"
# or "rain"/"rains" count as the same word — real headlines about the same
# event rarely share exact inflections. Deliberately crude (no real
# stemmer dependency); order matters, longest-suffix-first.
_STRIP_SUFFIXES = ("ing", "es", "ed", "s")


def _stem(word: str) -> str:
    for suffix in _STRIP_SUFFIXES:
        if word.endswith(suffix) and len(word) > len(suffix) + 2:
            return word[: -len(suffix)]
    return word


def _tokens(title: str) -> set[str]:
    return {_stem(w) for w in normalize_headline(title).split() if len(w) > 2}


def title_similarity(a: str, b: str) -> float:
    """Blends token-set Jaccard overlap (robust to reordered/rephrased
    headlines — "Heavy rain causes floods in Uttarakhand" vs "Uttarakhand
    flooding hits hill towns amid heavy rains" share little sequence but a
    lot of vocabulary) with a raw character-sequence ratio (catches
    near-verbatim reprints a token-set metric would treat identically to a
    much looser paraphrase). Takes the max of the two rather than an
    average so either signal alone can confirm a match.
    """
    tokens_a, tokens_b = _tokens(a), _tokens(b)
    jaccard = len(tokens_a & tokens_b) / len(tokens_a | tokens_b) if (tokens_a or tokens_b) else 0.0
    sequence_ratio = SequenceMatcher(None, normalize_headline(a), normalize_headline(b)).ratio()
    return max(jaccard, sequence_ratio)


def is_duplicate_title(a: str, b: str, threshold: float = DEDUP_TITLE_THRESHOLD) -> bool:
    return title_similarity(a, b) >= threshold


def any_duplicate_title(a: str, candidates: list[str], threshold: float = DEDUP_TITLE_THRESHOLD) -> bool:
    """True if `a` is a fuzzy duplicate of any of `candidates` — used to
    match against every headline merged into a card so far (see
    pipeline.public_events.find_or_merge_public_event), not just the
    card's original title, which otherwise drifts out of reach as more
    differently-worded sources accumulate."""
    return any(is_duplicate_title(a, c, threshold) for c in candidates)
