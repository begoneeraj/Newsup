# Integration Guide: Add Govt Promises to Your Existing groq_processor.py

## What You're Doing
Adding govt_promises routing to your **existing 2-hour pipeline**. No new files, no orphaned workflows. Just wiring up the module you already planned.

## Steps

### Step 1: Copy the Keywords
In your `groq_processor.py`, find your keyword detection section. Add this:

```python
GOVT_PROMISE_KEYWORDS = {
    # Budget / Money
    "crore", "lakh", "budget", "allocation", "expenditure", "fund",
    "fiscal", "outlay", "investment", "capex",
    # Infrastructure projects
    "metro", "highway", "expressway", "smart city", "airport",
    "railway station", "bridge", "dam", "irrigation", "power plant",
    "solar park", "road project", "port", "waterway", "pipeline",
    # Schemes / missions
    "scheme", "yojana", "mission", "abhiyan", "program", "initiative",
    "pm awas", "jan dhan", "ayushman bharat", "ujjwala", "swachh bharat",
    "digital india", "make in india", "semiconductor", "ai mission",
    "smart cities", "amrit bharat", "bullet train", "one nation one",
    "nal se jal", "saubhagya", "kisan samman", "fasal bima",
    "startup india", "skill india", "stand up india", "pradhan mantri",
    # Action words
    "launch", "inaugurate", "foundation stone", "deadline",
    "target date", "complete by", "commission", "operationalise",
    "pledge", "promise", "commit", "announce", "unveil", "approve",
    "delayed", "stalled", "behind schedule", "postponed", "scrapped",
}

def detect_govt_promise(headline: str, summary: str = "") -> bool:
    """Returns True if headline matches govt promise keywords."""
    text = (headline + " " + summary).lower()
    return any(kw in text for kw in GOVT_PROMISE_KEYWORDS)
```

### Step 2: Add the Extraction Prompt
In your `groq_processor.py`, add this new prompt template (alongside your existing student_crisis, court_case prompts):

```python
GOVT_PROMISE_EXTRACTION_PROMPT = """
You are extracting Indian government project/scheme data.

Headline: {headline}
Summary:  {summary}
Source:   {source}
URL:      {url}
Date:     {date}

Return ONLY valid JSON. No markdown. No backticks. No explanation.

{{
  "project_name"   : "Full official scheme/project name",
  "project_slug"   : "kebab-case-unique-id",
  "promise_type"   : "election|budget|scheme|infrastructure|policy",
  "ministry"       : "Ministry or department name",
  "status"         : "announced|started|ongoing|delayed|stalled|completed",
  "budget_crore"   : null or numeric value only,
  "announced_date" : null or "YYYY-MM-DD",
  "target_date"    : null or "YYYY-MM-DD",
  "beneficiaries"  : "Who benefits (farmers, urban poor, students, women, etc.)",
  "state"          : null or state name if state-level,
  "summary"        : "2-3 neutral sentences about what was promised and current status",
  "headline_genz"  : "≤15 words, casual Gen Z tone for young Indians",
  "source_url"     : "{url}"
}}

Enum rules:
  promise_type: election|budget|scheme|infrastructure|policy (only these 5)
  status: announced|started|ongoing|delayed|stalled|completed (only these 6)

If unknown, use null. Never hallucinate budget figures.
"""
```

### Step 3: Add the Routing Handler
In your `groq_processor.py`, add this function (alongside your existing `route_to_student_crisis`, `route_to_court_case` functions):

```python
def route_to_govt_promise_8b(headline: str, summary: str, source: str, url: str, date: str):
    """
    Extract govt promise schema using Llama3-8b-8192.
    Upsert to govt_promises table by project_slug.
    """
    prompt = GOVT_PROMISE_EXTRACTION_PROMPT.format(
        headline=headline,
        summary=summary,
        source=source,
        url=url,
        date=date,
    )
    
    try:
        response = groq_client.chat.completions.create(
            model="llama3-8b-8192",
            messages=[
                {
                    "role": "system",
                    "content": "You are a government promise tracker for India. Extract structured data. Return ONLY valid JSON."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            temperature=0.15,
            max_tokens=700,
        )
        
        raw_response = response.choices[0].message.content.strip()
        
        # Strip markdown fences if Groq adds them
        raw_response = re.sub(r"^```(?:json)?\s*", "", raw_response)
        raw_response = re.sub(r"\s*```$", "", raw_response)
        
        data = json.loads(raw_response)
        
        # Enum guard — Groq is probabilistic
        if data.get("promise_type") not in {"election", "budget", "scheme", "infrastructure", "policy"}:
            data["promise_type"] = "scheme"
        if data.get("status") not in {"announced", "started", "ongoing", "delayed", "stalled", "completed"}:
            data["status"] = "announced"
        
        # Budget must be numeric or null
        bc = data.get("budget_crore")
        if bc is not None:
            try:
                data["budget_crore"] = float(str(bc).replace(",", ""))
            except (ValueError, TypeError):
                data["budget_crore"] = None
        
        # Upsert to Supabase by project_slug
        slug = data.get("project_slug", "").strip()
        if slug:
            row = {k: v for k, v in data.items() if v is not None}
            row["updated_at"] = datetime.now(timezone.utc).isoformat()
            
            supabase.table("govt_promises").upsert(
                row, on_conflict="project_slug"
            ).execute()
            
            print(f"  ✅ GOVT_PROMISE: {data.get('project_name')} [{data.get('status')}]")
            return True
        else:
            print(f"  ⚠️  GOVT_PROMISE: No slug generated, skipped")
            return False
            
    except json.JSONDecodeError as e:
        print(f"  ❌ GOVT_PROMISE: JSON parse error — {e}")
        return False
    except Exception as e:
        print(f"  ❌ GOVT_PROMISE: Groq/Supabase error — {e}")
        return False
```

### Step 4: Wire Into Your Router
Find your main `route_headline()` or processing loop function. Add the govt_promise check in the right priority order:

```python
def process_headline(headline, summary, source, url, date):
    # Priority order (as per your checklist):
    if detect_student_crisis(headline, summary):
        return route_to_student_crisis_70b(...)
    
    if detect_court_case(headline, summary):
        return route_to_court_case_70b(...)
    
    # NEW: Govt promises (8b — speed tier)
    if detect_govt_promise(headline, summary):
        return route_to_govt_promise_8b(headline, summary, source, url, date)
    
    # Existing fallbacks
    if detect_ai_tech(headline, summary):
        return route_to_ai_tech_8b(...)
    
    return route_to_fact_check_8b(...)
```

### Step 5: Verify Imports
Make sure these are in your file (if not already):

```python
import re
import json
from datetime import datetime, timezone
```

---

## Testing

### Test 1: Manual Run
```bash
python groq_processor.py
```
Look for lines like:
```
  ✅ GOVT_PROMISE: PM Awas Yojana Phase 3 [ongoing]
  ✅ GOVT_PROMISE: Bullet Train Mumbai-Ahmedabad [delayed]
```

### Test 2: Check Supabase
Query your `govt_promises` table:
```sql
SELECT project_name, status, updated_at FROM govt_promises ORDER BY updated_at DESC LIMIT 10;
```

Should see fresh rows with timestamps from the last run.

### Test 3: Next GitHub Actions Run
Your 2-hour workflow will now:
1. Fetch news
2. Route to appropriate modules
3. Extract govt promises to the table
4. Upsert by project_slug (no duplicates, just status updates)

---

## That's It
- ✅ No orphaned files
- ✅ No new workflows
- ✅ Integrated into existing 2-hour pipeline
- ✅ Uses your existing Groq quota
- ✅ Slug-based upsert tracks project evolution
- ✅ Follows your routing priority order

The next headline containing "metro", "delayed", "yojana", etc. will automatically flow into govt_promises.
