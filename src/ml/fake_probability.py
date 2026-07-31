"""Combines the three fake-news signals (source track record, content model,
corroboration) into a single weighted score. See:
  - database.publisher_track_record.get_fake_rate     (source_credibility)
  - ml.fake_news_classifier.predict_fake_probability  (content_score)
  - ml.corroboration.get_corroboration_score          (corroboration_score)
"""

from __future__ import annotations

from database.publisher_track_record import get_fake_rate
from ml.corroboration import get_corroboration_score
from ml.fake_news_classifier import predict_fake_probability

# No track record yet for this (publisher_name, topic) -> neither trust nor
# distrust the source; sits exactly halfway between the two extremes.
_NEUTRAL_SOURCE_CREDIBILITY = 0.5

_SOURCE_WEIGHT = 0.4
_CONTENT_WEIGHT = 0.35
_CORROBORATION_WEIGHT = 0.25

_LIKELY_REAL_MAX = 0.4
_UNCERTAIN_MAX = 0.65


def calculate_fake_probability(article: dict) -> dict:
    """`article` needs: headline, body, publisher_name, topic.

    Returns a dict with fake_probability (0.0-1.0), a human-readable label,
    and the three component scores that produced it.
    """
    headline = article["headline"]
    body = article.get("body", "")
    publisher_name = article["publisher_name"]
    topic = article["topic"]

    fake_rate = get_fake_rate(publisher_name, topic)
    source_credibility = _NEUTRAL_SOURCE_CREDIBILITY if fake_rate is None else 1 - fake_rate

    content_score = predict_fake_probability(headline, body)
    corroboration_score = get_corroboration_score(headline)

    final_score = (
        _SOURCE_WEIGHT * (1 - source_credibility)
        + _CONTENT_WEIGHT * content_score
        + _CORROBORATION_WEIGHT * (1 - corroboration_score)
    )

    if final_score < _LIKELY_REAL_MAX:
        label = "Likely Real"
    elif final_score < _UNCERTAIN_MAX:
        label = "Uncertain"
    else:
        label = "Likely Fake"

    return {
        "fake_probability": round(final_score, 2),
        "label": label,
        "source_credibility": source_credibility,
        "content_score": content_score,
        "corroboration_score": corroboration_score,
    }
