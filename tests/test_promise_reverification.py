"""Verifies the "never fully_implemented on official-only evidence" rule
from the Government Promises Tracker evidence-trail expansion is enforced
in code, not just prompted - Groq is probabilistic (same lesson
ai_processor.groq_processor._sanitize_enums already encodes for enum
drift), so pipeline.promise_reverification._apply_business_rules must
independently re-check the evidence rather than trust the model's own
claim about which sources it used.

Runs against in-memory fakes of ai_processor.groq_processor and
database.supabase_client (installed into sys.modules before
pipeline.promise_reverification is imported), mirroring the pattern in
tests/test_dedup.py, rather than a live Groq/Supabase instance.
"""

from __future__ import annotations

import sys
import types

import pytest


def _independent_evidence_row():
    return {
        "source_type": "cag_report",
        "excerpt_summary": "CAG audit confirms the metro line was completed on schedule.",
        "observed_at": "2026-06-01T00:00:00+00:00",
    }


def _official_only_evidence_row():
    return {
        "source_type": "official_pib",
        "excerpt_summary": "Ministry press release announces the metro line was inaugurated.",
        "observed_at": "2026-06-01T00:00:00+00:00",
    }


@pytest.fixture()
def fake_modules_installed(monkeypatch):
    """Installs fake ai_processor.groq_processor / database.supabase_client
    into sys.modules before pipeline.promise_reverification is imported —
    required even for tests that only exercise the pure _apply_business_rules
    function, since importing the module at all triggers
    `from database.supabase_client import ...`, which in turn does
    `from supabase import Client, create_client` and fails in any
    environment without the real supabase package installed (see
    tests/test_dedup.py for the same pattern)."""
    fake_groq_module = types.ModuleType("ai_processor.groq_processor")
    fake_groq_module.process_govt_promise_reverification = lambda promise, evidence_rows: None
    monkeypatch.setitem(sys.modules, "ai_processor.groq_processor", fake_groq_module)

    fake_db_module = types.ModuleType("database.supabase_client")
    fake_db_module.fetch_promise_evidence = lambda promise_id: []
    fake_db_module.fetch_promises_needing_reverification = lambda: []
    fake_db_module.update_promise_verification = lambda promise_id, data: None
    monkeypatch.setitem(sys.modules, "database.supabase_client", fake_db_module)

    sys.modules.pop("pipeline.promise_reverification", None)
    import pipeline.promise_reverification as promise_reverification

    return promise_reverification


class TestApplyBusinessRules:
    """Direct unit tests of the pure guard function."""

    def test_downgrades_fully_implemented_without_independent_evidence(self, fake_modules_installed):
        payload = {"implementation_quality": "fully_implemented", "promise_id": "p1"}
        result = fake_modules_installed._apply_business_rules(payload, [_official_only_evidence_row()])

        assert result["implementation_quality"] == "partially_implemented"

    def test_allows_fully_implemented_with_independent_evidence(self, fake_modules_installed):
        payload = {"implementation_quality": "fully_implemented", "promise_id": "p1"}
        result = fake_modules_installed._apply_business_rules(
            payload, [_official_only_evidence_row(), _independent_evidence_row()]
        )

        assert result["implementation_quality"] == "fully_implemented"

    def test_leaves_non_fully_implemented_verdicts_untouched(self, fake_modules_installed):
        payload = {"implementation_quality": "on_paper_only", "promise_id": "p1"}
        result = fake_modules_installed._apply_business_rules(payload, [])

        assert result["implementation_quality"] == "on_paper_only"


class FakeGovtPromiseReverificationResult:
    """Stand-in for the GovtPromiseReverificationSchema instance
    process_govt_promise_reverification returns — only needs model_dump."""

    def __init__(self, **fields):
        self._fields = fields

    def model_dump(self, mode="json"):
        return dict(self._fields)


@pytest.fixture()
def promise_reverification_module(monkeypatch):
    fake_groq_module = types.ModuleType("ai_processor.groq_processor")
    fake_groq_module.process_govt_promise_reverification = lambda promise, evidence_rows: (
        FakeGovtPromiseReverificationResult(
            implementation_quality="fully_implemented",
            verification_confidence="high",
            official_claim="Government says the project is complete.",
            ground_reality="No independent confirmation found.",
            current_status="completed",
            broken_promise_flag=False,
            broken_promise_detail=None,
        )
    )
    monkeypatch.setitem(sys.modules, "ai_processor.groq_processor", fake_groq_module)

    updates: list[tuple[str, dict]] = []
    fake_db_module = types.ModuleType("database.supabase_client")
    fake_db_module.fetch_promise_evidence = lambda promise_id: [_official_only_evidence_row()]
    fake_db_module.fetch_promises_needing_reverification = lambda: []
    fake_db_module.update_promise_verification = lambda promise_id, data: updates.append(
        (promise_id, data)
    )
    monkeypatch.setitem(sys.modules, "database.supabase_client", fake_db_module)

    sys.modules.pop("pipeline.promise_reverification", None)
    import pipeline.promise_reverification as promise_reverification

    return promise_reverification, updates


def test_reverify_promise_persists_downgraded_quality(promise_reverification_module):
    promise_reverification, updates = promise_reverification_module

    promise = {"id": "promise-1", "project_name": "Test Metro", "current_status": "completed"}
    updated = promise_reverification.reverify_promise(promise)

    assert updated is True
    assert len(updates) == 1
    promise_id, data = updates[0]
    assert promise_id == "promise-1"
    assert data["implementation_quality"] == "partially_implemented", (
        "official_pib-only evidence should never let fully_implemented through, "
        "even when Groq's own output claims it"
    )


def test_reverify_promise_skips_when_no_evidence(monkeypatch):
    fake_db_module = types.ModuleType("database.supabase_client")
    fake_db_module.fetch_promise_evidence = lambda promise_id: []
    fake_db_module.fetch_promises_needing_reverification = lambda: []
    fake_db_module.update_promise_verification = lambda promise_id, data: pytest.fail(
        "should not persist when there is no evidence to re-verify against"
    )
    monkeypatch.setitem(sys.modules, "database.supabase_client", fake_db_module)

    sys.modules.pop("pipeline.promise_reverification", None)
    import pipeline.promise_reverification as promise_reverification

    updated = promise_reverification.reverify_promise({"id": "promise-2", "current_status": "ongoing"})

    assert updated is False
