#!/usr/bin/env python3
"""
govt_promise_seeder.py
──────────────────────
Dedicated fetcher + Groq extractor for the govt_promises table, targeting
PIB/PRS official sources the main 2-hour news pipeline doesn't specifically
prioritize (it draws from general news RSS, not government press releases).

This is a standalone complementary source, NOT a replacement for the
existing govt_promise routing already live in src/main.py
(route_expansion_module -> process_govt_promise -> upsert_govt_promise).
Both write to the same govt_promises table, keyed by project_slug, so a
project first seen here and later covered by mainstream news (or vice
versa) just gets its row updated, not duplicated.

Why standalone:
  - Govt promises don't break daily — weekly run is enough
  - Main 2-hour cron is too noisy for slug-based upsert tracking
  - This targets govt-specific sources the main pipeline deprioritizes

Run manually:   python "new genz implementation/govt_promise_seeder.py"
GitHub Actions: .github/workflows/govt_promises.yml (weekly, Monday 6 AM IST)

Requires env vars: SUPABASE_URL, SUPABASE_SERVICE_KEY, GROQ_API_KEY
(same names as every other script in this repo -- see src/main.py).
"""

import asyncio
import os
import re
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import feedparser
from supabase import create_client
from groq import Groq

# So "from fetchers.prs_legislative import ..." resolves regardless of CWD --
# this script lives outside src/, but reuses src/fetchers/prs_legislative.py
# (the working scraper) rather than duplicating it, since prsindia.org/feed
# (this script's original PRS source) is dead -- confirmed 404, and
# src/fetchers/rss_feeds.py already documents the same dead URL.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

# ─── Clients ────────────────────────────────────────────────────────────────

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
GROQ_API_KEY = os.environ["GROQ_API_KEY"]

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
groq_client = Groq(api_key=GROQ_API_KEY)

# Same env-overridable model resolution as src/ai_processor/groq_processor.py
# -- llama3-8b-8192 (the model this script originally hardcoded) has since
# been retired by Groq.
GROQ_MODEL = os.environ.get("GROQ_MODEL_FAST", "llama-3.1-8b-instant")
MAX_ENTRIES_PER_SOURCE = 20            # cap so we don't burn quota
GROQ_DELAY_SECONDS = 1.5              # free tier: ~30 req/min safe zone

# ─── Sources ────────────────────────────────────────────────────────────────
# Ordered by reliability for govt promise content.
# PIB = Press Information Bureau (official, highest signal)
# PRS = tracks bills + budget in parliament
# Others = supplementary

SOURCES = [
    # ── PIB feeds (official government press releases) ──
    {"name": "PIB - General", "url": "https://pib.gov.in/RssMain.aspx?ModId=6&Lang=1&Regid=3"},
    {"name": "PIB - Finance Ministry", "url": "https://pib.gov.in/RssMain.aspx?ModId=6&Lang=1&Regid=45"},
    {"name": "PIB - Infrastructure", "url": "https://pib.gov.in/RssMain.aspx?ModId=6&Lang=1&Regid=50"},
    {"name": "PIB - Science & Technology", "url": "https://pib.gov.in/RssMain.aspx?ModId=6&Lang=1&Regid=30"},
    # ── PRS Legislative Research (scraper, not RSS -- see fetch_feed) ──
    {"name": "PRS Legislative", "fetcher": "prs_scraper"},
    # ── Mainstream news (politics/policy desk) ──
    {"name": "The Hindu - National", "url": "https://www.thehindu.com/news/national/feeder/default.rss"},
    {"name": "Indian Express - India", "url": "https://indianexpress.com/section/india/feed/"},
    {"name": "NDTV - India", "url": "https://feeds.feedburner.com/ndtvnews-india-news"},
]

# ─── Keyword Filter ──────────────────────────────────────────────────────────
# Only headlines containing these words go to Groq. Saves quota.

PROMISE_KEYWORDS = [
    "crore", "lakh", "budget", "allocation", "expenditure", "fund",
    "fiscal", "outlay",
    "metro", "highway", "expressway", "smart city", "airport",
    "railway station", "bridge", "dam", "irrigation", "power plant",
    "solar park", "road project", "port", "waterway",
    "scheme", "yojana", "mission", "abhiyan", "program", "initiative",
    "pm awas", "jan dhan", "ayushman bharat", "ujjwala", "swachh bharat",
    "digital india", "make in india", "semiconductor", "ai mission",
    "smart cities", "amrit bharat", "bullet train", "one nation one",
    "nal se jal", "saubhagya", "kisan samman", "fasal bima",
    "startup india", "skill india", "stand up india",
    "launch", "inaugurate", "foundation stone", "deadline",
    "target date", "complete by", "commission", "operationalise",
    "pledge", "promise", "commit", "announce", "unveil",
    "delayed", "stalled", "behind schedule", "scrapped",
]

def is_govt_promise(title: str, summary: str = "") -> bool:
    text = (title + " " + summary).lower()
    return any(kw in text for kw in PROMISE_KEYWORDS)

# ─── Slug + Headline Hash ────────────────────────────────────────────────────

def slugify(text: str, max_len: int = 70) -> str:
    """Convert text to kebab-case slug."""
    text = text.lower()
    text = re.sub(r"[^a-z0-9\s-]", "", text)
    text = re.sub(r"\s+", "-", text.strip())
    text = re.sub(r"-+", "-", text)
    return text[:max_len].rstrip("-")

# ─── Groq Extraction ─────────────────────────────────────────────────────────
# Field names/enums here match the real govt_promises schema (see
# supabase/migrations/0012_expansion_modules.sql,
# 0013_promise_evidence_and_reverification.sql) -- NOT the
# promise_type/ministry/budget_crore/updated_at/headline_genz shape this
# script originally used, which don't exist as columns and would have
# failed every upsert with a Postgrest "column not found" error.

SYSTEM_PROMPT = (
    "You are a government promise tracker for India. "
    "Extract structured data from Indian news about government projects, schemes, and promises. "
    "Return ONLY valid JSON. No explanation. No markdown. No backticks."
)

VALID_CATEGORIES = {
    "metro", "highway", "smart_city", "ai_mission", "semiconductor",
    "social_scheme", "defence", "budget_allocation", "election_promise", "other",
}
VALID_STATUSES = {
    "announced", "started", "ongoing", "delayed", "stalled", "completed", "cancelled",
}

EXTRACTION_TEMPLATE = """News headline and context:

Headline : {headline}
Source   : {source}
Date     : {date}
URL      : {url}

Extract the government promise/project data and return a JSON object with EXACTLY these fields:

{{
  "project_name"    : "Official full name of the scheme/project/promise",
  "project_slug"    : "kebab-case-unique-id, e.g. pm-awas-yojana-urban-2024",
  "category"        : "one of: metro | highway | smart_city | ai_mission | semiconductor | social_scheme | defence | budget_allocation | election_promise | other",
  "announcing_body" : "Responsible ministry, department, or authority that announced this",
  "state"           : null or state name if this is a state-level (not national) project,
  "current_status"  : "one of: announced | started | ongoing | delayed | stalled | completed | cancelled",
  "budget_allocated_crore" : null or numeric value in crores INR (numbers only, no currency symbol),
  "announced_date"  : null or "YYYY-MM-DD",
  "promised_completion_date" : null or "YYYY-MM-DD",
  "beneficiaries"   : "Who benefits — e.g. farmers, urban poor, students, women",
  "headline_plain"  : "The original headline, plain text",
  "ai_summary"      : "2-3 neutral sentences: what was promised, current status, key facts",
  "genz_summary"    : "1-2 sentence casual Gen Z tone summary for young Indians, or null",
  "source_url"      : "{url}"
}}

Status guide:
  announced  = declared but not started
  started    = ground-breaking / work begun
  ongoing    = mid-execution, on track
  delayed    = behind original schedule
  stalled    = no progress / frozen
  completed  = delivered / inaugurated
  cancelled  = officially scrapped

If any field is genuinely unknown, use null (except category/announcing_body/current_status/
headline_plain/ai_summary, which are required — make a reasonable best guess rather than
leaving them empty). Never hallucinate budget figures.
"""

def extract_with_groq(headline: str, source_name: str, pub_date: str, url: str) -> dict | None:
    prompt = EXTRACTION_TEMPLATE.format(
        headline=headline,
        source=source_name,
        date=pub_date,
        url=url,
    )
    raw = ""
    try:
        resp = groq_client.chat.completions.create(
            model=GROQ_MODEL,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            temperature=0.15,
            max_tokens=700,
        )
        raw = resp.choices[0].message.content.strip()
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)
        return json.loads(raw)

    except json.JSONDecodeError as e:
        print(f"    [JSON ERROR] {e}")
        print(f"    Raw: {raw[:300]}")
        return None
    except Exception as e:
        print(f"    [GROQ ERROR] {e}")
        return None

def sanitize(data: dict) -> dict:
    """Clamp enum fields to valid values. Groq is probabilistic."""
    if data.get("category") not in VALID_CATEGORIES:
        data["category"] = "other"
    if data.get("current_status") not in VALID_STATUSES:
        data["current_status"] = "announced"
    data["state_or_national"] = "state" if data.get("state") else "national"
    bc = data.get("budget_allocated_crore")
    if bc is not None:
        try:
            data["budget_allocated_crore"] = float(str(bc).replace(",", ""))
        except (ValueError, TypeError):
            data["budget_allocated_crore"] = None
    # Groq occasionally returns the JSON string "null", a bare year
    # ("2025"), or other non-ISO text for date fields instead of a real
    # "YYYY-MM-DD" string or the JSON null literal -- Postgres rejects any
    # of those as invalid date input, so validate the format here rather
    # than let the upsert fail.
    for date_field in ("announced_date", "promised_completion_date"):
        value = data.get(date_field)
        if not (isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value.strip())):
            data[date_field] = None
    return data

# ─── Supabase Upsert ─────────────────────────────────────────────────────────

def upsert_promise(data: dict) -> bool:
    """
    Slug-based upsert: first insert creates a row, subsequent runs (from
    this seeder or the main news pipeline's own govt_promise routing --
    both key on project_slug) update status/summary as the project evolves.
    """
    slug = (data.get("project_slug") or "").strip()
    if not slug:
        # Groq occasionally omits project_slug despite the prompt -- derive
        # one from project_name rather than dropping the row.
        slug = slugify(data.get("project_name") or "")
    if not slug:
        print("    [SKIP] No project_slug generated")
        return False

    row = {
        "project_name": data.get("project_name"),
        "project_slug": slug,
        "category": data.get("category"),
        "announcing_body": data.get("announcing_body"),
        "state_or_national": data.get("state_or_national"),
        "state": data.get("state"),
        "announced_date": data.get("announced_date"),
        "promised_completion_date": data.get("promised_completion_date"),
        "current_status": data.get("current_status"),
        "budget_allocated_crore": data.get("budget_allocated_crore"),
        "beneficiaries": data.get("beneficiaries"),
        "headline_plain": data.get("headline_plain"),
        "ai_summary": data.get("ai_summary"),
        "genz_summary": data.get("genz_summary"),
        "source_url": data.get("source_url"),
        "last_updated": datetime.now(timezone.utc).isoformat(),
    }

    # Required-not-null columns: fall back to a safe default rather than
    # skip the row outright if Groq left one empty.
    row["category"] = row["category"] or "other"
    row["announcing_body"] = row["announcing_body"] or "Unspecified"
    row["current_status"] = row["current_status"] or "announced"
    row["headline_plain"] = row["headline_plain"] or data.get("project_name") or slug
    row["ai_summary"] = row["ai_summary"] or row["headline_plain"]

    row = {k: v for k, v in row.items() if v is not None}

    try:
        supabase.table("govt_promises").upsert(row, on_conflict="project_slug").execute()
        return True
    except Exception as e:
        print(f"    [SUPABASE ERROR] {e}")
        return False

# ─── Feed Fetcher ────────────────────────────────────────────────────────────

_FEED_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
}


def _fetch_prs_bills() -> list[dict]:
    """PRS via src/fetchers/prs_legislative.py's scraper (async) instead of
    RSS -- prsindia.org/feed is dead (404, confirmed independently of the
    same finding already noted in src/fetchers/rss_feeds.py)."""
    from fetchers.prs_legislative import fetch_all_prs_bills

    items = asyncio.run(fetch_all_prs_bills())
    return [
        {
            "title": item.title,
            "summary": item.text,
            "link": item.url,
            "published": item.published_at.strftime("%Y-%m-%d") if item.published_at else datetime.now().strftime("%Y-%m-%d"),
        }
        for item in items
    ][:MAX_ENTRIES_PER_SOURCE]


def fetch_feed(source: dict) -> list[dict]:
    """Parse RSS feed, return list of {title, summary, link, published}.

    pib.gov.in silently 403s feedparser's default (non-browser) User-Agent,
    which feedparser reports as a 301 with zero entries rather than an
    exception -- easy to mistake for "PIB just has no matching news" rather
    than a block. A browser UA fixes it (confirmed by fetching the same URL
    with and without one).
    """
    if source.get("fetcher") == "prs_scraper":
        try:
            return _fetch_prs_bills()
        except Exception as e:
            print(f"  [FEED ERROR] {source['name']}: {e}")
            return []

    try:
        feed = feedparser.parse(source["url"], request_headers=_FEED_HEADERS)
        entries = []
        for entry in feed.entries[:MAX_ENTRIES_PER_SOURCE]:
            entries.append({
                "title": getattr(entry, "title", ""),
                "summary": getattr(entry, "summary", ""),
                "link": getattr(entry, "link", ""),
                "published": getattr(entry, "published", datetime.now().strftime("%Y-%m-%d")),
            })
        return entries
    except Exception as e:
        print(f"  [FEED ERROR] {source['name']}: {e}")
        return []

# ─── Entry Point ─────────────────────────────────────────────────────────────

def run():
    print(f"\n{'=' * 55}")
    print(f"  Govt Promise Seeder  |  {datetime.now().strftime('%Y-%m-%d %H:%M IST')}")
    print(f"{'=' * 55}\n")

    saved = 0
    skipped = 0
    errors = 0

    for source in SOURCES:
        print(f"[FEED] {source['name']}")
        entries = fetch_feed(source)
        print(f"    {len(entries)} entries fetched")

        for entry in entries:
            title = entry["title"]
            summary = entry["summary"]
            link = entry["link"]
            pubdate = entry["published"]

            if not is_govt_promise(title, summary):
                skipped += 1
                continue

            print(f"\n  [MATCH]  {title[:72]}...")

            data = extract_with_groq(title, source["name"], pubdate, link)
            if not data:
                errors += 1
                time.sleep(GROQ_DELAY_SECONDS)
                continue

            data = sanitize(data)

            ok = upsert_promise(data)
            if ok:
                saved += 1
                print(f"  [SAVED]  {data.get('project_name', '?')}  [{data.get('current_status')}]")
            else:
                errors += 1

            time.sleep(GROQ_DELAY_SECONDS)

        print()

    print(f"{'=' * 55}")
    print(f"  Saved/Updated : {saved}")
    print(f"  Skipped       : {skipped}  (not a promise headline)")
    print(f"  Errors        : {errors}")
    print(f"{'=' * 55}\n")


if __name__ == "__main__":
    run()
