"""Sentence-embedding helper for semantic deduplication.

Uses the free, local `sentence-transformers/all-MiniLM-L6-v2` model (384-dim
output) so dedup checks cost nothing and don't hit any external API.
"""

from __future__ import annotations

from functools import lru_cache

from sentence_transformers import SentenceTransformer

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"


@lru_cache(maxsize=1)
def _get_model() -> SentenceTransformer:
    return SentenceTransformer(MODEL_NAME)


def embed_text(text: str) -> list[float]:
    """Return a 384-dim embedding vector for the given text."""
    vector = _get_model().encode(text, normalize_embeddings=True)
    return vector.tolist()
