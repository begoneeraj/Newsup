"""Word-boundary keyword matching, shared by main.py's expansion-module
routing and pipeline.underreported_topics. A naive substring check
false-positives on short acronyms inside ordinary words (e.g. "ED" alone
matching "delayed") -- \\b keeps a keyword list readable while only matching
it as a whole word/phrase. Extracted from main.py's original
_keyword_matches so both callers share one implementation instead of
drifting out of sync.
"""

from __future__ import annotations

import re


def keyword_matches(keywords: list[str], text: str) -> bool:
    return any(re.search(rf"\b{re.escape(k.lower())}\b", text) for k in keywords)
