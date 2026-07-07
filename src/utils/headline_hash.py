"""Fast exact-match dedup pre-filter, checked before the embedding-based
semantic dedup in main.py (see supabase/migrations/0007_rate_limiting_and_headline_hash.sql).

Normalizes away case/punctuation/whitespace differences so the same wire
story reprinted with trivial formatting differences across outlets still
hashes identically, without needing an embedding computation or Groq call.
"""

from __future__ import annotations

import hashlib
import re

_NON_ALNUM_RE = re.compile(r"[^a-z0-9\s]")
_WHITESPACE_RE = re.compile(r"\s+")


def normalize_headline(title: str) -> str:
    lowered = title.lower()
    stripped = _NON_ALNUM_RE.sub("", lowered)
    return _WHITESPACE_RE.sub(" ", stripped).strip()


def headline_hash(title: str) -> str:
    return hashlib.sha256(normalize_headline(title).encode("utf-8")).hexdigest()
