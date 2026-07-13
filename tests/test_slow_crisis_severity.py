"""Verifies pipeline.slow_crisis_quant._compute_severity - the pure,
no-I/O, no-LLM function that decides a tracked Slow Crisis's severity.
This is the trust-critical rule for the whole module: the severity verdict
must come only from arithmetic over official readings, never from Groq.
"""

from __future__ import annotations

from pipeline.slow_crisis_quant import PM25_CRITICAL_THRESHOLD, _compute_severity


def _points(values: list[float]) -> list[dict]:
    return [{"value": v} for v in values]


def test_empty_data_points_is_stable():
    assert _compute_severity([]) == "stable"


def test_latest_reading_at_or_above_critical_threshold_is_critical():
    data_points = _points([50, 60, 70, PM25_CRITICAL_THRESHOLD])
    assert _compute_severity(data_points) == "critical"

    data_points_above = _points([50, 60, 70, PM25_CRITICAL_THRESHOLD + 10])
    assert _compute_severity(data_points_above) == "critical"


def test_too_few_points_for_trend_is_stable_when_not_critical():
    # Below the 2*_TREND_WINDOW+1 points needed to compare windows.
    assert _compute_severity(_points([50, 55])) == "stable"


def test_worsening_trend_detected():
    # Previous window ~50, recent window ~80 (60% increase).
    data_points = _points([48, 50, 52, 78, 80, 82])
    assert _compute_severity(data_points) == "worsening"


def test_improving_trend_detected():
    # Previous window ~100, recent window ~60 (40% decrease).
    data_points = _points([98, 100, 102, 58, 60, 62])
    assert _compute_severity(data_points) == "improving"


def test_stable_trend_within_threshold():
    # Previous window ~100, recent window ~103 (3% change, below 10% threshold).
    data_points = _points([98, 100, 102, 101, 103, 105])
    assert _compute_severity(data_points) == "stable"
