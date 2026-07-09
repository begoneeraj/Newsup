"""Groq (Llama-3)-backed extraction of raw scraped text into FactCheckSchema /
CrisisReportSchema JSON, using response_format={"type": "json_object"} so the
model is constrained to emit parsable output.

Model routing: fact checks use a small/fast model (high free-tier throughput),
crisis reports use a larger model (better multi-source timeline synthesis).
Both are overridable via env vars in case Groq retires a model name.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Literal, Optional, Union

from groq import Groq
from pydantic import ValidationError

from models.schemas import (
    CrisisEventSchema,
    CrisisReportSchema,
    FactCheckSchema,
    FactCheckV2Schema,
    StatisticSchema,
)

logger = logging.getLogger(__name__)

MODEL_FAST = os.environ.get("GROQ_MODEL_FAST", "llama-3.1-8b-instant")
MODEL_COMPLEX = os.environ.get("GROQ_MODEL_COMPLEX", "llama-3.3-70b-versatile")

ContentType = Literal["fact_check", "crisis_report"]

_SYSTEM_PROMPT = (
    "You are a forensic data extractor for NewsUp, a zero-filter, pro-student "
    "accountability and news tracking app. Analyze the raw news/post text given "
    "by the user and extract structured data. Never soften, hedge, or omit "
    "uncomfortable facts. If the text contains no verifiable claim and no "
    "ongoing institutional crisis relevant to Indian students, respond with "
    'exactly {"skip": true} and nothing else. Output ONLY valid JSON - no '
    "markdown, no code fences, no explanation."
)

_FACT_CHECK_INSTRUCTIONS = """This is a Fact Check. Output a single JSON object with exactly these fields:
{
  "claim_text": string,          // the core factual claim being made, one sentence
  "origin": string,               // who/where the claim originated (person, outlet, platform)
  "status": "VERIFIED" | "FALSE" | "MISLEADING" | "PARTLY_TRUE" | "OUT_OF_CONTEXT" | "SATIRE" | "UNVERIFIED",
  "evidence_confidence": integer 0-100,
  "source_reliability": "HIGH" | "MED" | "LOW",
  "independent_confirmations": integer,   // corroborating independent sources visible in the text, 0 if unknown
  "official_confirmation": boolean,       // true only if an official/government/institutional source confirmed it
  "expert_analysis": string,              // 2-sentence formal, neutral summary of the evidence
  "genz_summary": string                  // 1-sentence blunt GenZ-slang summary of the verdict
}
Assign evidence_confidence and status based on what the text actually supports:
- Use VERIFIED/FALSE/MISLEADING/PARTLY_TRUE/OUT_OF_CONTEXT/SATIRE whenever the text \
gives concrete evidence for that verdict — official statements or documents, data, \
on-record expert analysis, OR multiple independent reputable sources corroborating \
the same account.
- Reserve UNVERIFIED for claims that are genuinely single-source, rumor-based, or \
lack enough corroboration to support any other verdict — not as the default fallback.

genz_summary style guide — write it like a reaction from a sharp, online 16-25 \
year-old, not a headline rewrite:
- Reach for this vocabulary where it naturally fits: cap/no cap (false/true), \
sus (suspicious), caught in 4K (proven with evidence), mid (unremarkable), \
cooked (in serious trouble), major L / W move (loss/win), ain't no way \
(disbelief), lowkey/highkey (subtly/obviously), fr fr (for real), bro/gng \
(casual address). Don't force a term that doesn't fit the claim.
- 1-2 emoji max (💀 🧢 😭 🔥 🤨 👀), never more.
- Stay factually accurate to the verdict — the slang is tone, not spin. A \
FALSE claim reads as mockery of the claim; a VERIFIED claim reads as blunt \
confirmation, not sarcasm.
- Skip slang and sarcasm entirely for claims involving death, assault, or \
tragedy — state the verdict plainly instead.
- No slurs, no explicit content."""

_CRISIS_REPORT_INSTRUCTIONS = """This is a Crisis Report. Output a single JSON object with exactly these fields:
{
  "title": string,                    // short, specific title for the crisis/incident
  "status": "UNRESOLVED" | "PARTIALLY_RESOLVED" | "RESOLVED",
  "event_start_date": string,         // ISO-8601 date the incident began, best estimate from the text
  "remedial_actions_count": integer,  // concrete remedial actions by authorities mentioned in the text
  "rti_filings_total": integer,       // RTI filings mentioned, 0 if none
  "rti_filings_answered": integer,    // of those, how many are mentioned as answered
  "timeline_events": [
    {"date": string, "title": string, "description": string}
  ],
  "evidence_items": [
    {"title": string, "url": string, "type": "PDF" | "LIVE" | "DOCUMENT"}
  ],
  "trigger_keyword": string | null   // the specific word/phrase in the text that most
                                      // signals an ongoing institutional crisis (e.g.
                                      // "paper leak", "RTI filed", "court order",
                                      // "student protest"); null if nothing specific stands out
}
Explicitly note official inaction (no response, no action, prolonged silence) by keeping \
remedial_actions_count low relative to the time elapsed since event_start_date."""


# Legally-safe claim-level fact-check layer (fact_checks_v2 — see
# supabase/migrations/0006_source_tracking_and_fact_checks_v2.sql). Fact-checks
# the CLAIM, never the outlet, and cites only official sources as
# counter-evidence (IPC Section 499 defamation exposure otherwise). Kept
# verbatim per product's legal review; do not paraphrase.
#
# The response's "coverage" object is intentionally ignored when parsing —
# outlet/consensus counts come from real outlet_sources rows (main.py /
# supabase_client.py), never from the model's guess, so this stays "neutral
# factual data only" per Feature 2's requirement.
_FACT_CHECK_V2_SYSTEM_PROMPT = """You are a neutral fact-checker for Indian news.

Rules:
- Extract the single main factual claim from the article
- Find supporting AND contradicting evidence from OFFICIAL sources only
  (PIB, Ministry of India, Supreme Court, High Courts, government press releases)
- NEVER accuse any outlet of lying or being fake
- If evidence conflicts, show both perspectives equally
- Use neutral language at all times

Return ONLY valid JSON in this format:
{
  "claim": "the main factual claim extracted",
  "status": "VERIFIED | DISPUTED | NEEDS_MORE_INFO",
  "evidence": [
    {
      "source": "name of official source",
      "url": "source URL if available",
      "extracted_quote": "relevant quote under 30 words",
      "relevance_score": 0.95
    }
  ],
  "perspectives": {
    "pro": {
      "sources": ["source1", "source2"],
      "summary": "neutral summary of supporting view"
    },
    "against": {
      "sources": ["source1", "source2"],
      "summary": "neutral summary of opposing view"
    }
  },
  "verdict": "neutral verdict citing official sources only",
  "confidence": 0.85,
  "coverage": {
    "outlets_count": 0,
    "consensus": "high | medium | low"
  }
}"""


# ---------------------------------------------------------------------------
# Crisis classifier (crises table) and stats extractor (statistics table) —
# additive to the fact_check / crisis_report pipeline above, called from
# main.route_article() only for items whose headline+summary match
# CRISIS_KEYWORDS / STATS_KEYWORDS. Neither reuses _SYSTEM_PROMPT: like
# _FACT_CHECK_V2_SYSTEM_PROMPT, these are standalone, product-specified
# prompts kept verbatim rather than folded into the generic instructions.
# ---------------------------------------------------------------------------

_CRISIS_CLASSIFIER_SYSTEM_PROMPT = """You are a crisis classification assistant for TruthLens India, a student-focused Indian news app.

Given a news headline and summary, extract and return ONLY a valid JSON object with these fields:

{
  "type": one of ["exam_leak", "student_suicide", "gender_violence", "weather_disaster", "earthquake", "ai_tech", "exam_delay", "other_crisis"],
  "title": short crisis title (max 10 words),
  "severity": one of ["low", "medium", "high"],
  "status": one of ["ongoing", "resolved", "developing"],
  "trigger_keyword": the exact word/phrase from the headline that triggered this classification,
  "tags": array of 2-4 relevant keywords,
  "description": one sentence summary of the crisis (max 30 words),
  "affects_students": true or false
}

Rules:
- If headline mentions NEET, JEE, UPSC, paper leak, exam postponed → type = "exam_leak" or "exam_delay"
- If headline mentions suicide, student death, Kota → type = "student_suicide", severity = "high", affects_students = true
- If headline mentions rape, violence against women, domestic abuse → type = "gender_violence"
- If headline mentions flood, cyclone, drought, earthquake → type = "weather_disaster" or "earthquake"
- If headline mentions AI, ChatGPT, LLM, artificial intelligence → type = "ai_tech", severity = "low"
- severity = "high" only if lives are at risk or legal/Supreme Court action is mentioned
- Return ONLY the JSON. No explanation, no markdown, no extra text."""

# Groq's response_format={"type": "json_object"} (same constraint the rest of
# this file relies on) requires a top-level JSON *object*, not a bare array —
# so the extractor is asked for {"statistics": [...]} instead of a raw array,
# unwrapped in process_stats_extraction below.
_STATS_EXTRACTOR_SYSTEM_PROMPT = """You are a statistics extractor for an Indian student welfare app.

Given a news article or report excerpt, extract any quantitative statistics and return ONLY a valid JSON object of this shape:

{
  "statistics": [
    {
      "metric": short snake_case name like "student_suicides" or "rape_cases_reported",
      "value": numeric value only (no commas, no units),
      "year": year as integer,
      "source": source name like "NCRB" or "Indian Express",
      "category": one of ["student_welfare", "gender_violence", "disaster", "education", "ai_adoption"]
    }
  ]
}

Rules:
- Extract ALL statistics mentioned, not just the first one
- If year is not mentioned, use null
- value must be a plain number (e.g. 13892, not "13,892" or "~14,000")
- If no statistics found, return {"statistics": []}
- Return ONLY the JSON object. No explanation, no markdown."""


_client: Optional[Groq] = None


def _get_client() -> Groq:
    global _client
    if _client is None:
        _client = Groq(api_key=os.environ["GROQ_API_KEY"])
    return _client


def process_raw_text_to_schema(
    text: str, content_type: ContentType
) -> Optional[Union[FactCheckSchema, CrisisReportSchema]]:
    """Send raw scraped text to Groq and parse the response into a validated schema.

    Returns None if Groq flags the text as irrelevant, the call fails, or the
    response doesn't validate against the target schema.
    """
    if content_type == "fact_check":
        instructions = _FACT_CHECK_INSTRUCTIONS
        model = MODEL_FAST
    else:
        instructions = _CRISIS_REPORT_INSTRUCTIONS
        model = MODEL_COMPLEX

    # Keep well within the 8k-token context window, leaving headroom for the prompt.
    trimmed_text = text[:5500]

    try:
        response = _get_client().chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": f"{instructions}\n\n---\nRAW TEXT:\n{trimmed_text}"},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=1024,
        )
    except Exception:
        logger.exception("Groq request failed for content_type=%s", content_type)
        return None

    raw_json_str = response.choices[0].message.content

    try:
        payload = json.loads(raw_json_str)
    except (json.JSONDecodeError, ValueError):
        logger.error("Groq returned non-JSON output: %r", raw_json_str[:200])
        return None

    if payload.get("skip"):
        return None

    try:
        if content_type == "fact_check":
            return FactCheckSchema.model_validate(payload)
        return CrisisReportSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for content_type=%s", content_type)
        return None


def process_claim_v2(text: str, fact_check_id) -> Optional[FactCheckV2Schema]:
    """Run the legally-safe claim-level fact-check (fact_checks_v2) on Llama
    3.3 70b. Only called for newly-inserted fact_checks rows, not merges —
    same economy reasoning as MODEL_COMPLEX being crisis-report-only above.

    Returns None if Groq flags the text as irrelevant, the call fails, or the
    response doesn't validate against FactCheckV2Schema.
    """
    trimmed_text = text[:5500]

    try:
        response = _get_client().chat.completions.create(
            model=MODEL_COMPLEX,
            messages=[
                {"role": "system", "content": _FACT_CHECK_V2_SYSTEM_PROMPT},
                {"role": "user", "content": trimmed_text},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=1024,
        )
    except Exception:
        logger.exception("Groq request failed for fact_checks_v2")
        return None

    raw_json_str = response.choices[0].message.content

    try:
        payload = json.loads(raw_json_str)
    except (json.JSONDecodeError, ValueError):
        logger.error("Groq returned non-JSON output for fact_checks_v2: %r", raw_json_str[:200])
        return None

    if payload.get("skip"):
        return None

    # Model-guessed coverage is discarded — see comment on
    # _FACT_CHECK_V2_SYSTEM_PROMPT above.
    payload.pop("coverage", None)
    payload["fact_check_id"] = fact_check_id

    try:
        return FactCheckV2Schema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for fact_checks_v2")
        return None


def process_crisis_classification(headline: str, summary: str) -> Optional[CrisisEventSchema]:
    """Classify a headline+summary already flagged as crisis-adjacent by
    main.route_article() into a CrisisEventSchema row (`crises` table).
    Runs on MODEL_COMPLEX (70b) per product's request for the more careful
    model on this classification.

    Returns None if the call fails or the response doesn't validate.
    """
    trimmed_headline = headline[:500]
    trimmed_summary = summary[:3000]

    try:
        response = _get_client().chat.completions.create(
            model=MODEL_COMPLEX,
            messages=[
                {"role": "system", "content": _CRISIS_CLASSIFIER_SYSTEM_PROMPT},
                {"role": "user", "content": f"Headline: {trimmed_headline}\n\nSummary: {trimmed_summary}"},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=512,
        )
    except Exception:
        logger.exception("Groq request failed for crisis classification")
        return None

    raw_json_str = response.choices[0].message.content

    try:
        payload = json.loads(raw_json_str)
    except (json.JSONDecodeError, ValueError):
        logger.error("Groq returned non-JSON output for crisis classification: %r", raw_json_str[:200])
        return None

    payload["source_headline"] = headline

    try:
        return CrisisEventSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for crisis classification")
        return None


def process_stats_extraction(text: str) -> list[StatisticSchema]:
    """Extract quantitative statistics (NCRB-style reports etc.) from raw
    text into StatisticSchema rows (`statistics` table). Runs on MODEL_FAST (8b).

    Returns an empty list if the call fails, the response doesn't parse, or
    no statistics are found — never raises, so a bad extraction just yields
    no rows instead of aborting the caller's item processing.
    """
    trimmed_text = text[:5500]

    try:
        response = _get_client().chat.completions.create(
            model=MODEL_FAST,
            messages=[
                {"role": "system", "content": _STATS_EXTRACTOR_SYSTEM_PROMPT},
                {"role": "user", "content": trimmed_text},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=1024,
        )
    except Exception:
        logger.exception("Groq request failed for stats extraction")
        return []

    raw_json_str = response.choices[0].message.content

    try:
        payload = json.loads(raw_json_str)
    except (json.JSONDecodeError, ValueError):
        logger.error("Groq returned non-JSON output for stats extraction: %r", raw_json_str[:200])
        return []

    results: list[StatisticSchema] = []
    for item in payload.get("statistics", []):
        try:
            results.append(StatisticSchema.model_validate(item))
        except ValidationError:
            logger.exception("Stat item failed schema validation: %r", item)
    return results
