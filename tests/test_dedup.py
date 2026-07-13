"""Verifies the fix described in the project plan: three differently-worded
articles about the same real-world event ("2026 Uttarakhand floods"), from
three different source buckets, should collapse into a single public_events
card with merge_count == 3 and one entry in each source bucket — not three
separate cards.

Runs against an in-memory fake of database.supabase_client (installed into
sys.modules before pipeline.public_events is imported) rather than a live
Supabase instance, so it exercises the real fuzzy-match/merge logic in
pipeline.public_events.find_or_merge_public_event without needing network
access or credentials.
"""

from __future__ import annotations

import sys
import types
from datetime import datetime, timezone

import pytest


class FakePublicEventsTable:
    """Minimal in-memory stand-in for the public_events table, just enough
    to exercise find_recent_public_events / merge_public_event / merge_lookback_days
    the way the real Supabase-backed versions in
    src/database/supabase_client.py behave."""

    def __init__(self):
        self.rows: dict[str, dict] = {}
        self._next_id = 1

    def insert(self, schema: dict) -> str:
        row_id = f"evt-{self._next_id}"
        self._next_id += 1
        row = dict(schema)
        row["id"] = row_id
        row.setdefault("merge_count", 1)
        row.setdefault("status", None)
        self.rows[row_id] = row
        return row_id

    def find_recent(self, event_type: str, state, since_iso: str, limit: int = 25) -> list[dict]:
        candidates = [
            row
            for row in self.rows.values()
            if row["event_type"] == event_type and row.get("status") != "resolved"
        ]
        if state:
            candidates = [row for row in candidates if row.get("state") == state]
        return [
            {
                "id": row["id"],
                "title": row["title"],
                "merge_count": row["merge_count"],
                "severity": row.get("severity"),
                "official_sources": row.get("official_sources", []),
                "media_sources": row.get("media_sources", []),
                "reddit_sources": row.get("reddit_sources", []),
                "youtube_sources": row.get("youtube_sources", []),
            }
            for row in candidates[:limit]
        ]

    def merge(self, existing_id: str, bucket: str, new_entry: dict) -> None:
        row = self.rows[existing_id]
        row[bucket] = [*row.get(bucket, []), new_entry]
        row["merge_count"] += 1


@pytest.fixture()
def fake_events_table():
    return FakePublicEventsTable()


@pytest.fixture()
def public_events_module(fake_events_table, monkeypatch):
    """Installs a fake database.supabase_client into sys.modules so
    pipeline.public_events's local `from database.supabase_client import
    ...` (see find_or_merge_public_event) resolves to the fake instead of
    the real Supabase-backed module — the real one requires network
    credentials and isn't needed to test the merge/fuzzy-match logic."""
    fake_module = types.ModuleType("database.supabase_client")
    fake_module.find_recent_public_events = fake_events_table.find_recent
    fake_module.merge_lookback_days = lambda event_type: 4
    fake_module.merge_public_event = fake_events_table.merge
    monkeypatch.setitem(sys.modules, "database.supabase_client", fake_module)

    # Force a fresh import of pipeline.public_events so its module-level
    # state doesn't leak between tests, and so the local import inside
    # find_or_merge_public_event picks up the fake module above.
    sys.modules.pop("pipeline.public_events", None)
    import pipeline.public_events as public_events

    return public_events


def _make_item(models, *, source: str, title: str):
    return models.RawContentItem(
        source=source,
        origin=source,
        title=title,
        text=f"{title}. Uttarakhand floods 2026 rescue operations underway.",
        url=f"https://example.com/{source}",
        published_at=datetime.now(timezone.utc),
    )


def test_three_worded_differently_flood_articles_merge_into_one_card(public_events_module, fake_events_table):
    import models.schemas as models

    public_events = public_events_module
    headlines = [
        ("imd", "Heavy rain causes floods in Uttarakhand"),
        ("google_news", "Uttarakhand flooding hits hill towns amid heavy rains"),
        ("reddit", "Uttarakhand flood death toll rises as rescue operations continue"),
    ]

    merged_id = None
    for source, title in headlines:
        item = _make_item(models, source=source, title=title)
        schema = public_events.build_public_event(
            item,
            source_table="fact_checks",
            source_id="00000000-0000-0000-0000-000000000000",
            embedding=[0.0] * 384,
            headline_hash=None,
            importance_score=50,
            fact_check=models.FactCheckSchema(
                claim_text=title,
                origin=source,
                status=models.FactCheckStatus.VERIFIED,
                evidence_confidence=70,
                source_reliability=models.SourceReliability.HIGH,
            ),
        )

        existing_id = public_events.find_or_merge_public_event(schema, item)
        if existing_id is None:
            merged_id = fake_events_table.insert(schema)
        else:
            assert existing_id == merged_id, "second/third article should merge into the first card"

    assert merged_id is not None
    row = fake_events_table.rows[merged_id]
    assert row["merge_count"] == 3, "three sources should have merged into one card"
    assert row["event_type"] == "flood"
    assert len(row.get("official_sources", [])) == 1
    assert len(row.get("media_sources", [])) == 1
    assert len(row.get("reddit_sources", [])) == 1


def test_unrelated_event_in_same_state_does_not_merge(public_events_module, fake_events_table):
    """Guards against the fuzzy matcher being so permissive it merges two
    genuinely different crises that happen to share an event_type/state —
    e.g. a flood and, weeks/topics apart, an earthquake report gated on a
    completely different keyword set shouldn't collide. Uses two flood
    stories with essentially no shared vocabulary/place to keep it a
    same-type comparison (the real guardrail against unrelated *disaster
    types* colliding is the event_type filter itself, exercised here by
    construction — this test targets the title-similarity threshold)."""
    import models.schemas as models

    public_events = public_events_module

    def _schema_for(source: str, title: str):
        item = _make_item(models, source=source, title=title)
        return item, public_events.build_public_event(
            item,
            source_table="fact_checks",
            source_id="00000000-0000-0000-0000-000000000000",
            embedding=[0.0] * 384,
            headline_hash=None,
            importance_score=50,
            fact_check=models.FactCheckSchema(
                claim_text=title,
                origin=source,
                status=models.FactCheckStatus.VERIFIED,
                evidence_confidence=70,
                source_reliability=models.SourceReliability.HIGH,
            ),
        )

    item1, schema1 = _schema_for("imd", "Heavy rain causes floods in Uttarakhand")
    assert public_events.find_or_merge_public_event(schema1, item1) is None
    fake_events_table.insert(schema1)

    item2, schema2 = _schema_for("google_news", "Flash floods in Assam displace thousands after Brahmaputra breach")
    result = public_events.find_or_merge_public_event(schema2, item2)
    assert result is None, "a differently-located, differently-worded flood story should not merge"
