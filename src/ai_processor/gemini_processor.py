"""Gemini-backed extraction of raw scraped text into FactCheckSchema /
CrisisReportSchema JSON, using response_mime_type="application/json" so the
model is constrained to emit parsable output.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Literal, Optional, Union

from google import genai
from google.genai import types
from pydantic import ValidationError

from models.schemas import CrisisReportSchema, FactCheckSchema

logger = logging.getLogger(__name__)

# Overridable via env var in case the pinned free-tier model name changes.
MODEL_NAME = os.environ.get("GEMINI_MODEL", "gemini-2.0-flash")

ContentType = Literal["fact_check", "crisis_report"]

_SYSTEM_PROMPT = (
    "You are a forensic data extractor for NewsUp, a zero-filter, pro-student "
    "accountability and news tracking app. Analyze the raw news/post text given "
    "by the user and extract structured data. Never soften, hedge, or omit "
    "uncomfortable facts. If the text contains no verifiable claim and no "
    "ongoing institutional crisis relevant to Indian students, respond with "
    'exactly {"skip": true} and nothing else.'
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


_client: Optional[genai.Client] = None


def _get_client() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    return _client


def process_raw_text_to_schema(
    text: str, content_type: ContentType
) -> Optional[Union[FactCheckSchema, CrisisReportSchema]]:
    """Send raw scraped text to Gemini and parse the response into a validated schema.

    Returns None if Gemini flags the text as irrelevant, the call fails, or the
    response doesn't validate against the target schema.
    """
    instructions = (
        _FACT_CHECK_INSTRUCTIONS if content_type == "fact_check" else _CRISIS_REPORT_INSTRUCTIONS
    )
    prompt = f"{instructions}\n\n---\nRAW TEXT:\n{text}"

    try:
        response = _get_client().models.generate_content(
            model=MODEL_NAME,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=_SYSTEM_PROMPT,
                response_mime_type="application/json",
                temperature=0.2,
            ),
        )
    except Exception:
        logger.exception("Gemini request failed for content_type=%s", content_type)
        return None

    try:
        payload = json.loads(response.text)
    except (json.JSONDecodeError, ValueError):
        logger.error("Gemini returned non-JSON output: %r", response.text[:200])
        return None

    if payload.get("skip"):
        return None

    try:
        if content_type == "fact_check":
            return FactCheckSchema.model_validate(payload)
        return CrisisReportSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Gemini output failed schema validation for content_type=%s", content_type)
        return None
