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

from models.schemas import CrisisReportSchema, FactCheckSchema

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
Assign evidence_confidence and status conservatively: default to UNVERIFIED and a low score \
unless the text itself contains concrete evidence (official statements, documents, data)."""

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
  ]
}
Explicitly note official inaction (no response, no action, prolonged silence) by keeping \
remedial_actions_count low relative to the time elapsed since event_start_date."""


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
