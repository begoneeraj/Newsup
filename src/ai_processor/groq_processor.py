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
    AiTechReportSchema,
    ConfidenceClassificationSchema,
    CourtCaseSchema,
    CrisisEventSchema,
    CrisisReportSchema,
    FactCheckSchema,
    FactCheckV2Schema,
    GovtPromiseSchema,
    StatisticSchema,
    StudentCrisisReportSchema,
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


# Deliberately terser than _CRISIS_CLASSIFIER_SYSTEM_PROMPT above: this backs
# a high-volume per-article endpoint (POST /classify, api_server.py) called
# for every raw_articles doc the GDELT ingestion pipeline writes -- up to
# ~100 per 15-minute run -- so it runs on MODEL_FAST, not MODEL_COMPLEX, and
# asks for a plain confidence/label pair rather than a full crisis record.
_CONFIDENCE_CLASSIFIER_SYSTEM_PROMPT = """You are a crisis relevance scorer for TruthLens India, a student-focused Indian news app.

Given an article's title, summary, and content, return ONLY a valid JSON object with these fields:

{
  "confidence": integer 0-100, how confident you are this is a genuine, ongoing crisis/incident worth surfacing (not routine news, not opinion, not satire),
  "label": short snake_case category, one of ["exam_leak", "student_suicide", "gender_violence", "weather_disaster", "earthquake", "civil_unrest", "public_health", "conflict", "corruption", "other_crisis", "not_crisis"]
}

Rules:
- confidence = 0 and label = "not_crisis" if the article is routine news, opinion, satire, or promotional content
- confidence should reflect how clearly the text supports an ongoing crisis, not how severe it sounds
- Return ONLY the JSON object. No explanation, no markdown, no extra text."""


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


_FALLBACK_CONFIDENCE_CLASSIFICATION = ConfidenceClassificationSchema(confidence=0, label="not_crisis")


def process_confidence_classification(
    title: str, summary: str, content: str
) -> ConfidenceClassificationSchema:
    """Scores a single article for crisis relevance as a plain
    confidence/label pair. Backs POST /classify (api_server.py), which the
    TypeScript crisisClassifier Cloud Function calls via GROQ_PROCESSOR_URL
    as the base score that applyToneHeuristic() then adjusts.

    Unlike the other process_* functions in this module, this always
    returns a valid ConfidenceClassificationSchema rather than None on
    failure -- the HTTP endpoint must answer every request with a body the
    caller can parse, so an unclassifiable article safely defaults to
    confidence=0, label="not_crisis" instead of surfacing a 500.
    """
    trimmed_title = title[:500]
    trimmed_summary = summary[:3000]
    trimmed_content = content[:5000]

    try:
        response = _get_client().chat.completions.create(
            model=MODEL_FAST,
            messages=[
                {"role": "system", "content": _CONFIDENCE_CLASSIFIER_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": (
                        f"Title: {trimmed_title}\n\n"
                        f"Summary: {trimmed_summary}\n\n"
                        f"Content: {trimmed_content}"
                    ),
                },
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=128,
        )
    except Exception:
        logger.exception("Groq request failed for confidence classification")
        return _FALLBACK_CONFIDENCE_CLASSIFICATION

    raw_json_str = response.choices[0].message.content

    try:
        payload = json.loads(raw_json_str)
    except (json.JSONDecodeError, ValueError):
        logger.error("Groq returned non-JSON output for confidence classification: %r", raw_json_str[:200])
        return _FALLBACK_CONFIDENCE_CLASSIFICATION

    try:
        return ConfidenceClassificationSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for confidence classification")
        return _FALLBACK_CONFIDENCE_CLASSIFICATION


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


# ---------------------------------------------------------------------------
# Expansion modules — student crisis / AI & tech / govt promises / court
# cases. See truthlens_expansion_prompt.md (Parts 1-4). Routed via
# main.route_expansion_module() (Part 0), additive to the existing
# fact_check/crisis_report/crisis/stats pipeline above. Kept verbatim from
# the source spec's SCOPE/RULE sections per "implement strictly"; only the
# JSON schema examples are trimmed since the target Pydantic schema already
# enforces field shape.
# ---------------------------------------------------------------------------

_STUDENT_CRISIS_SYSTEM_PROMPT = """You are TruthLens India's Student Crisis Analyst.
Your job is to extract structured facts from Indian news articles about
student distress, exam irregularities, and education system failures.

SCOPE - process articles about:
1. Student suicides and mental health crises
2. Paper leaks and exam irregularities (ANY exam - NEET, JEE, CUET,
   UPSC, GATE, CAT, CLAT, NDA, board exams, state-level exams)
3. Student protests and agitations
4. Coaching centre deaths and misconduct
5. University/college crackdowns, expulsions, or fee disputes
6. Scholarship scams or cancellations

DO NOT focus exclusively on NEET. If the article is about JEE, CUET,
UP Board, or any other exam, treat it with equal importance.

TRAGEDY RULE: For all articles involving student death, suicide, or
serious mental health crisis - do NOT use Gen Z slang in any field.
Use plain, respectful, factual language. If crisis_type is "suicide" or
"mental_health", headline_genz must be null.

Return ONLY valid JSON with exactly these fields:
{
  "exam_or_context": "string - which exam or context (NEET / JEE / UPSC / Board / General student issue etc.)",
  "crisis_type": "paper_leak | suicide | protest | coaching_misconduct | university_action | scholarship | mental_health | other",
  "severity": "critical | high | medium | low",
  "affected_count": "number or null - estimated number of students affected",
  "state": "string or null - Indian state where incident occurred",
  "institution": "string or null - name of exam board, university, or coaching centre",
  "government_response": "string or null - what authorities have said or done",
  "student_demand": "string or null - what students are demanding if it is a protest",
  "court_involvement": "boolean - is any court hearing this matter",
  "fact_check_flag": "true | false - does this article make specific numerical claims that need verification",
  "headline_plain": "string - factual 1-line summary",
  "headline_genz": "string or null - Gen Z version (null if crisis_type is suicide or mental_health)",
  "key_facts": ["array", "of", "verified", "claims", "from", "the", "article"],
  "missing_info": "string or null - what crucial information the article does NOT mention",
  "next_step_to_watch": "string - what event, deadline, or official action to track next"
}"""

_AI_TECH_SYSTEM_PROMPT = """You are TruthLens India's AI and Technology Analyst.
Your job is to extract structured facts from news articles about
artificial intelligence, tech policy, and the global/Indian tech industry.

SCOPE - process articles about:
1. New AI models, launches, and capability announcements (GPT, Claude,
   Gemini, Llama, Mistral, Grok, DeepSeek, Indian models etc.)
2. AI regulation and policy (EU AI Act, India AI policy, US executive orders)
3. Semiconductor industry - fabs, chip design, export controls
4. AI funding rounds, acquisitions, and startup news
5. Deepfakes, synthetic media, and AI misuse in India
6. IndiaAI mission, C-DAC, IIT lab announcements
7. Robotics, drones, autonomous systems
8. Data centre investments in India
9. Big Tech (Google, Meta, Microsoft, OpenAI, Anthropic) India activity
10. Global AI incidents - accidents, controversies, bans

INDIA LENS RULE: Always note whether this news has a direct India angle
(Indian companies, Indian policy, impact on Indian users). If it is a
purely global story, mark india_relevance as false.

Return ONLY valid JSON with exactly these fields:
{
  "tech_category": "ai_model | ai_policy | semiconductor | funding | deepfake | india_ai_mission | robotics | data_centre | big_tech | incident | other",
  "india_relevance": "boolean - does this directly involve India or Indian users",
  "india_angle": "string or null - how this affects India specifically",
  "companies_involved": ["array of company names mentioned"],
  "countries_involved": ["array of countries mentioned"],
  "claim_type": "launch | regulation | funding | controversy | research | acquisition | ban | other",
  "hype_check": "overhyped | neutral | understated - is the article inflating the news",
  "technical_accuracy": "accurate | minor_errors | misleading | cannot_verify",
  "headline_plain": "string - factual 1-line summary",
  "headline_genz": "string - Gen Z version using tech slang naturally",
  "key_facts": ["array", "of", "specific", "claims", "with", "numbers"],
  "what_this_means_for_india": "string - plain English explanation of the India impact",
  "next_milestone": "string or null - what event or deadline to watch next",
  "sources_to_verify": ["list of official sources that can confirm the claims"]
}"""

_GOVT_PROMISE_SYSTEM_PROMPT = """You are TruthLens India's Government Accountability Analyst.
Your job is to extract structured data from news articles about
government announcements, schemes, and infrastructure projects -
so citizens can track whether promises are kept.

SCOPE - track promises and projects across:
1. Election manifesto promises (national and state)
2. Union Budget allocations and schemes
3. Infrastructure projects:
   - Metro rail lines (city, corridor, phase)
   - Highways and expressways (NH number, route)
   - Smart City Mission projects
   - AMRUT projects
4. Technology missions:
   - IndiaAI Mission
   - Semiconductor Mission (chips, fabs, ATMP)
   - Digital India
   - BharatNet
5. Social schemes (PM Awas, Ayushman Bharat, PM Kisan etc.)
6. Defence procurement and Make-in-India targets

STATUS CLASSIFICATION - always assign exactly ONE status:
- "announced" - only declared, no ground action yet
- "started" - foundation stone laid, tender issued, or construction begun
- "ongoing" - actively in progress, within expected timeline
- "delayed" - past promised deadline or official delay acknowledged
- "stalled" - no activity for 6+ months or funding frozen
- "completed" - officially inaugurated or fully delivered
- "cancelled" - officially dropped

ACCOUNTABILITY RULE: If the article mentions a previous promise or
deadline that was missed, always capture it in broken_promise_flag.

Return ONLY valid JSON with exactly these fields:
{
  "project_name": "string - official name of project, scheme, or promise",
  "project_slug": "string - lowercase-hyphenated unique identifier e.g. mumbai-metro-line-3",
  "category": "metro | highway | smart_city | ai_mission | semiconductor | social_scheme | defence | budget_allocation | election_promise | other",
  "announcing_body": "string - which ministry, CM, PM, or party made this promise",
  "state_or_national": "national | state - scope of the project",
  "state": "string or null - which state if state-level",
  "announced_date": "YYYY-MM-DD or null",
  "promised_completion_date": "YYYY-MM-DD or null",
  "revised_completion_date": "YYYY-MM-DD or null",
  "current_status": "announced | started | ongoing | delayed | stalled | completed | cancelled",
  "budget_allocated_crore": "number or null - in crore INR",
  "budget_spent_crore": "number or null - if mentioned",
  "broken_promise_flag": "boolean - has a previous deadline been missed",
  "broken_promise_detail": "string or null - what was promised vs what happened",
  "beneficiaries": "string or null - who this scheme/project benefits",
  "headline_plain": "string - factual 1-line update on this project",
  "ai_summary": "string - 2-3 sentence plain-English summary of where this project stands and what citizens should know",
  "key_facts": ["array", "of", "specific", "figures", "and", "dates"],
  "next_milestone": "string or null - next expected event or deadline",
  "verification_sources": ["RTI portal", "ministry website", "or other sources to verify"]
}"""

_COURT_CASE_SYSTEM_PROMPT = """You are TruthLens India's Legal Affairs Analyst.
Your job is to extract structured data from news articles about
significant court cases in India - so citizens can follow important
legal battles over time.

SCOPE - track cases from:
1. Supreme Court of India - all significant matters
2. High Courts - landmark or widely reported cases
3. Constitutional benches - Article 370, reservation, fundamental rights
4. Corporate litigation - NCLT, NCLAT, insolvency matters
5. Environmental litigation - NGT orders, pollution cases
6. Criminal matters - ED, CBI, NIA chargesheets and trials
7. Electoral disputes - ECI, election tribunals
8. PIL matters - public interest litigation affecting citizens

CASE IDENTIFICATION RULE: If this article is about a CONTINUING case
(one that has been in court before), extract the case number or parties
so it can be matched to an existing record in the database.
If it is a NEW case, mark is_new_case as true.

BALANCE RULE: Courts have multiple parties. Always capture BOTH sides
of the argument - petitioner and respondent claims. Do not frame the
summary to favour either side.

LEGAL JARGON RULE: The ai_summary must be written in plain English
that a Class 10 student can understand. No Latin, no jargon.
Explain what the case means for ordinary citizens.

Return ONLY valid JSON with exactly these fields:
{
  "case_title": "string - e.g. 'Petitioner Name vs Union of India'",
  "case_number": "string or null - official case number if mentioned",
  "case_slug": "string - lowercase-hyphenated identifier e.g. neet-ug-2024-paper-leak-sc",
  "is_new_case": "boolean - true if this appears to be a new filing",
  "court": "supreme_court | high_court | ngt | nclt | nclat | cbi_court | other",
  "high_court_state": "string or null - which state's High Court",
  "case_category": "constitutional | criminal | environmental | corporate | electoral | pil | service_matter | other",
  "petitioner": "string - who filed the case or appeal",
  "respondent": "string - who is being challenged",
  "core_legal_question": "string - the ONE central question the court is deciding, in plain English",
  "petitioner_argument": "string - what the petitioner is arguing, plain English",
  "respondent_argument": "string or null - what the government or respondent is arguing",
  "last_hearing_date": "YYYY-MM-DD or null",
  "last_hearing_outcome": "string or null - what happened in the last hearing",
  "next_hearing_date": "YYYY-MM-DD or null",
  "current_order": "string or null - any active stay, notice, or interim order",
  "key_documents": ["chargesheet", "PIL petition", "SLP", "reply affidavit - list what documents exist"],
  "impact_if_petitioner_wins": "string - what changes for citizens if the petitioner wins",
  "impact_if_respondent_wins": "string - what stays the same or changes if the government wins",
  "headline_plain": "string - factual 1-line summary of latest development",
  "ai_summary": "string - 3-4 sentence plain-English summary of the whole case, written for a Class 10 student",
  "key_facts": ["array", "of", "specific", "dates", "orders", "and", "claims"],
  "follow_up_trigger": "string or null - what event should trigger re-processing this case"
}"""


def _run_expansion_module(
    *, system_prompt: str, model: str, text: str, max_tokens: int = 1024
) -> Optional[dict]:
    """Shared Groq call + JSON parse for the four expansion modules below.
    Returns the raw parsed payload dict, or None on any failure (network,
    non-JSON output). Schema validation is left to each caller since every
    module validates against a different Pydantic schema.
    """
    trimmed_text = text[:5500]

    try:
        response = _get_client().chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": trimmed_text},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=max_tokens,
        )
    except Exception:
        logger.exception("Groq request failed for expansion module")
        return None

    raw_json_str = response.choices[0].message.content

    try:
        return json.loads(raw_json_str)
    except (json.JSONDecodeError, ValueError):
        logger.error("Groq returned non-JSON output for expansion module: %r", raw_json_str[:200])
        return None


# Groq is probabilistic and occasionally returns an enum value close to but
# not exactly one of the allowed strings (e.g. "super-critical" instead of
# "critical", "8b" casing drift, etc.). Rather than let one bad enum field
# drop an otherwise-good extraction (ValidationError -> None), coerce known
# enum fields to a safe default and keep the record. field -> (valid values,
# default when invalid/missing).
_ENUM_SANITIZE_RULES: dict[type, dict[str, tuple[set[str], str]]] = {
    StudentCrisisReportSchema: {
        "severity": ({"critical", "high", "medium", "low"}, "medium"),
        "crisis_type": (
            {
                "paper_leak", "suicide", "protest", "coaching_misconduct",
                "university_action", "scholarship", "mental_health", "other",
            },
            "other",
        ),
    },
    AiTechReportSchema: {
        "tech_category": (
            {
                "ai_model", "ai_policy", "semiconductor", "funding", "deepfake",
                "india_ai_mission", "robotics", "data_centre", "big_tech",
                "incident", "other",
            },
            "other",
        ),
        "claim_type": (
            {
                "launch", "regulation", "funding", "controversy", "research",
                "acquisition", "ban", "other",
            },
            "other",
        ),
        "hype_check": ({"overhyped", "neutral", "understated"}, "neutral"),
        "technical_accuracy": (
            {"accurate", "minor_errors", "misleading", "cannot_verify"},
            "cannot_verify",
        ),
    },
    GovtPromiseSchema: {
        "category": (
            {
                "metro", "highway", "smart_city", "ai_mission", "semiconductor",
                "social_scheme", "defence", "budget_allocation",
                "election_promise", "other",
            },
            "other",
        ),
        "state_or_national": ({"national", "state"}, "national"),
        "current_status": (
            {
                "announced", "started", "ongoing", "delayed", "stalled",
                "completed", "cancelled",
            },
            "announced",
        ),
    },
    CourtCaseSchema: {
        "court": (
            {"supreme_court", "high_court", "ngt", "nclt", "nclat", "cbi_court", "other"},
            "other",
        ),
        "case_category": (
            {
                "constitutional", "criminal", "environmental", "corporate",
                "electoral", "pil", "service_matter", "other",
            },
            "other",
        ),
    },
}


def _sanitize_enums(payload: dict, schema_class: type) -> dict:
    """Coerce out-of-range enum strings in `payload` to a safe default for
    the given schema, in place. See _ENUM_SANITIZE_RULES."""
    for field, (valid_values, default) in _ENUM_SANITIZE_RULES.get(schema_class, {}).items():
        value = payload.get(field)
        if not isinstance(value, str) or value not in valid_values:
            if value is not None:
                logger.warning(
                    "Groq returned invalid %s enum value %r for %s; defaulting to %r",
                    field, value, schema_class.__name__, default,
                )
            payload[field] = default
    return payload


def process_student_crisis(headline: str, text: str) -> Optional[StudentCrisisReportSchema]:
    """Student Crisis module (Part 1) - NEET/JEE/CUET/UPSC/board-exam paper
    leaks, student suicides, protests, coaching misconduct. Runs on
    MODEL_COMPLEX (70b) per spec."""
    payload = _run_expansion_module(
        system_prompt=_STUDENT_CRISIS_SYSTEM_PROMPT,
        model=MODEL_COMPLEX,
        text=f"Headline: {headline}\n\n{text}",
    )
    if payload is None:
        return None
    _sanitize_enums(payload, StudentCrisisReportSchema)
    try:
        return StudentCrisisReportSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for student_crisis")
        return None


def process_ai_tech(headline: str, text: str) -> Optional[AiTechReportSchema]:
    """AI & Tech World module (Part 2). Runs on MODEL_FAST (8b) per spec."""
    payload = _run_expansion_module(
        system_prompt=_AI_TECH_SYSTEM_PROMPT,
        model=MODEL_FAST,
        text=f"Headline: {headline}\n\n{text}",
    )
    if payload is None:
        return None
    _sanitize_enums(payload, AiTechReportSchema)
    try:
        return AiTechReportSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for ai_tech")
        return None


def process_govt_promise(headline: str, text: str) -> Optional[GovtPromiseSchema]:
    """Government Promises Tracker module (Part 3). Runs on MODEL_FAST (8b)
    per spec."""
    payload = _run_expansion_module(
        system_prompt=_GOVT_PROMISE_SYSTEM_PROMPT,
        model=MODEL_FAST,
        text=f"Headline: {headline}\n\n{text}",
    )
    if payload is None:
        return None
    _sanitize_enums(payload, GovtPromiseSchema)
    try:
        return GovtPromiseSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for govt_promise")
        return None


def process_court_case(headline: str, text: str) -> Optional[CourtCaseSchema]:
    """Court Case Tracker module (Part 4). Runs on MODEL_COMPLEX (70b) per
    spec."""
    payload = _run_expansion_module(
        system_prompt=_COURT_CASE_SYSTEM_PROMPT,
        model=MODEL_COMPLEX,
        text=f"Headline: {headline}\n\n{text}",
    )
    if payload is None:
        return None
    _sanitize_enums(payload, CourtCaseSchema)
    try:
        return CourtCaseSchema.model_validate(payload)
    except ValidationError:
        logger.exception("Groq output failed schema validation for court_case")
        return None
