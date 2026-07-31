"""Shared input-validation helpers for api_server.py's request bodies.

Centralized here so every endpoint that accepts external text/identifier
fields applies the same rules rather than each Pydantic model re-inventing
its own checks.
"""

from __future__ import annotations

import re

import bleach

# Applies to any free-text field sourced from an external caller (headline,
# article body/summary, ...).
MAX_TEXT_LENGTH = 2000

# A rate-keyword alone (e.g. "select" in "select committee") is common in
# ordinary news text, so this only flags a DML/DDL keyword that also appears
# alongside SQL-statement syntax (FROM/INTO/TABLE/SET/WHERE/VALUES/DATABASE)
# within the same field, not the keyword on its own.
_SQL_INJECTION_PATTERN = re.compile(
    r"(?i)\b(DROP|DELETE|INSERT|UPDATE|UNION|SELECT)\b"
    r"(?:\s+\w+){0,6}?\s+\b(TABLE|FROM|INTO|SET|WHERE|VALUES|DATABASE)\b"
)

PUBLISHER_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9\s\-]{1,100}$")

ALLOWED_TOPICS = [
    "politics", "crime", "business", "science", "sports",
    "world", "education", "health", "technology", "other",
]


class TextValidationError(ValueError):
    pass


def clean_text_field(value: str, *, field_name: str = "text") -> str:
    """Validates and sanitizes a headline/article-text field: strips
    whitespace and HTML tags, enforces the length cap, and rejects payloads
    that look like a SQL injection attempt.
    """
    value = value.strip()

    if len(value) > MAX_TEXT_LENGTH:
        raise TextValidationError(f"{field_name} exceeds maximum length of {MAX_TEXT_LENGTH} characters")

    value = bleach.clean(value, tags=[], attributes={}, strip=True).strip()

    if _SQL_INJECTION_PATTERN.search(value):
        raise TextValidationError(f"{field_name} contains disallowed SQL-like syntax")

    return value


def validate_publisher_name(value: str) -> str:
    value = value.strip()
    if not PUBLISHER_NAME_PATTERN.match(value):
        raise TextValidationError(
            "publisher_name must be alphanumeric with spaces/hyphens only, 1-100 characters"
        )
    return value


def validate_topic(value: str) -> str:
    if value not in ALLOWED_TOPICS:
        raise TextValidationError(f"topic must be one of {ALLOWED_TOPICS}")
    return value
