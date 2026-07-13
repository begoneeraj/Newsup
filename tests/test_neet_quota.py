"""Verifies the NEET daily quota gate in main.process_expansion_module: once
NEET_DAILY_QUOTA NEET-tagged items have been ingested in the last 24h,
further NEET articles are skipped *before* the Groq call (main._is_neet_item
is a cheap pre-check on raw text, since exam identity is otherwise only
known from Groq's own output). Non-NEET student-crisis items must be
unaffected regardless of the NEET count.

main.py is import-safe with no live credentials (get_client()/_get_client()
are lazy, checked directly before writing this test), so this monkeypatches
names directly on the already-imported `main` module rather than faking
sys.modules like tests/test_promise_reverification.py does for the
pipeline.* modules, which do require that heavier pattern.
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

import main
from models.schemas import RawContentItem


def _make_item(title: str) -> RawContentItem:
    return RawContentItem(
        source="google_news",
        origin="NEET leak",
        title=title,
        text=f"{title}. Full article body about the exam situation.",
        url=f"https://example.com/{hash(title)}",
        published_at=datetime.now(timezone.utc),
    )


@pytest.fixture(autouse=True)
def _no_dedup_no_sampling(monkeypatch):
    """Keep every other gate in process_expansion_module a no-op so only the
    NEET quota gate under test can cause a skip."""
    monkeypatch.setattr(main, "find_by_headline_hash", lambda table, h: None)
    monkeypatch.setattr(main, "EXPANSION_MODULE_SAMPLE_RATE", 1.0)


def test_neet_item_skipped_over_quota(monkeypatch):
    monkeypatch.setattr(main, "count_recent_student_crisis_reports", lambda keyword: main.NEET_DAILY_QUOTA)

    called = {"process": False, "insert": False}
    monkeypatch.setattr(main, "process_student_crisis", lambda *a, **k: called.__setitem__("process", True))
    monkeypatch.setattr(main, "insert_student_crisis_report", lambda *a, **k: called.__setitem__("insert", True))

    item = _make_item("NEET paper leak sparks fresh protests across states")
    main.process_expansion_module(item, item.text)

    assert called["process"] is False, "NEET item at/over quota must be skipped before the Groq call"
    assert called["insert"] is False


def test_neet_item_processed_under_quota(monkeypatch):
    monkeypatch.setattr(main, "count_recent_student_crisis_reports", lambda keyword: main.NEET_DAILY_QUOTA - 1)

    called = {"process": False}

    class _FakeResult:
        source_url = None
        headline_hash = None

        def model_dump(self, mode="json"):
            return {}

    def _fake_process_student_crisis(*a, **k):
        called["process"] = True
        return _FakeResult()

    monkeypatch.setattr(main, "process_student_crisis", _fake_process_student_crisis)
    monkeypatch.setattr(main, "insert_student_crisis_report", lambda *a, **k: "fake-id")
    monkeypatch.setattr(main, "time", type("T", (), {"sleep": staticmethod(lambda *_: None)}))

    item = _make_item("NEET paper leak sparks fresh protests across states")
    main.process_expansion_module(item, item.text)

    assert called["process"] is True, "NEET item under quota should still be processed normally"


def test_non_neet_student_crisis_item_ignores_neet_quota(monkeypatch):
    # NEET count is way over quota, but this item isn't about NEET at all.
    monkeypatch.setattr(main, "count_recent_student_crisis_reports", lambda keyword: main.NEET_DAILY_QUOTA + 10)

    called = {"process": False}

    class _FakeResult:
        source_url = None
        headline_hash = None

        def model_dump(self, mode="json"):
            return {}

    def _fake_process_student_crisis(*a, **k):
        called["process"] = True
        return _FakeResult()

    monkeypatch.setattr(main, "process_student_crisis", _fake_process_student_crisis)
    monkeypatch.setattr(main, "insert_student_crisis_report", lambda *a, **k: "fake-id")
    monkeypatch.setattr(main, "time", type("T", (), {"sleep": staticmethod(lambda *_: None)}))

    item = _make_item("JEE Main exam postponed after technical glitch")
    main.process_expansion_module(item, item.text)

    assert called["process"] is True, "non-NEET exam items must not be gated by the NEET quota"
