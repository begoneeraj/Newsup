"""Verifies route_expansion_module's priority order after adding
slow_crisis/science_research: student_crisis > court_tracker > govt_promise
> slow_crisis > ai_tech > science_research. This is the highest-risk
regression point in the Content Diversification changes since every
expansion module shares this one function - a misplaced insertion could
silently steal traffic from an earlier-priority module.
"""

from __future__ import annotations

import main


def test_student_crisis_wins_over_slow_crisis_on_overlapping_text():
    # "air pollution" (slow_crisis) + "student protest" (student_crisis) in
    # the same text - student_crisis must win since it's checked first.
    module, _ = main.route_expansion_module(
        "Student protest erupts over air pollution near exam centre", ""
    )
    assert module == "student_crisis"


def test_govt_promise_wins_over_slow_crisis_on_overlapping_text():
    module, _ = main.route_expansion_module(
        "Metro line inaugurated as city battles worsening air quality", ""
    )
    assert module == "govt_promise"


def test_slow_crisis_wins_over_ai_tech_on_overlapping_text():
    module, _ = main.route_expansion_module(
        "AI model predicts air quality trends amid rising AQI levels", ""
    )
    assert module == "slow_crisis"


def test_ai_tech_wins_over_science_research_on_overlapping_text():
    module, _ = main.route_expansion_module(
        "New AI model trained on research paper data shows strong results", ""
    )
    assert module == "ai_tech"


def test_slow_crisis_matches_on_its_own():
    module, _ = main.route_expansion_module("Delhi air quality turns severe amid smog", "")
    assert module == "slow_crisis"


def test_science_research_matches_on_its_own():
    module, _ = main.route_expansion_module("ISRO scientists publish new research paper on Mars orbiter", "")
    assert module == "science_research"


def test_unrelated_text_matches_none():
    module, _ = main.route_expansion_module("Local bakery wins award for best bread", "")
    assert module == "none"
