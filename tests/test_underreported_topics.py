"""Verifies pipeline.underreported_topics._compute_gap_score - the pure,
no-I/O, no-LLM function that turns real niche-vs-mainstream counts into the
gap_score. Same trust-critical rule as tests/test_slow_crisis_severity.py:
the score must come only from arithmetic over real fetched counts, never
from Groq.

Formula (see _compute_gap_score's own docstring): log2((niche+1)/(mainstream+1)).
Laplace-smoothed (the +1s) to avoid dividing by/logging zero, unbounded in
both directions (unlike a 0-1 clamped ratio) - a topic can be arbitrarily
more or less covered by niche sources than mainstream ones.
"""

from __future__ import annotations

import math

from pipeline.underreported_topics import _compute_gap_score


def test_no_activity_scores_zero():
    assert _compute_gap_score(0, 0) == 0.0


def test_mainstream_only_scores_negative():
    # No niche/official activity but mainstream coverage exists - well
    # covered, not underreported, so the score goes negative rather than
    # clamping at zero.
    score = _compute_gap_score(0, 50)
    assert score < 0.0
    assert score == math.log2(1 / 51)


def test_niche_only_scores_positive():
    score = _compute_gap_score(10, 0)
    assert score > 0.0
    assert score == math.log2(11 / 1)


def test_equal_coverage_scores_zero():
    assert _compute_gap_score(5, 5) == 0.0


def test_mainstream_exceeding_niche_scores_negative():
    # More mainstream coverage than official activity - not underreported.
    score = _compute_gap_score(2, 20)
    assert score < 0.0
    assert score == math.log2(3 / 21)


def test_niche_exceeding_mainstream_scores_positive():
    score = _compute_gap_score(8, 2)
    assert score > 0.0
    assert score == math.log2(9 / 3)
