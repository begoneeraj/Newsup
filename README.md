# TruthLens India

**Fact-checking and crisis tracking for Indian news — built for students, not algorithms.**

TruthLens India pulls in Indian news from a dozen different places, runs every claim through an AI fact-checker, and tracks slow-moving institutional crises (paper leaks, RTI stonewalling, court cases) that normal news cycles forget about after 48 hours. No ads, no engagement-bait, no outlet gets called a liar — just claims, evidence, and receipts.

---

## What it actually does

- **Fact-checks, automatically.** Every headline gets a claim extracted and checked against the evidence in the article itself — verdict, confidence score, and a plain-language "expert analysis," refreshed every couple of hours.
- **Tracks crises, not just headlines.** Reddit threads about NEET paper leaks, RTI filings, and court orders get escalated to a bigger model that builds out a timeline instead of a one-line verdict — because "student protests over exam leak" is a story that plays out over months, not a single article.
- **Shows its work.** Every fact-check can show which outlets covered it, how many, and what the consensus looks like — plain outlet counts and names, never "widely reported" spin.
- **Never accuses an outlet.** A separate, legally-conservative fact-check layer only cites official sources (PIB, ministries, courts, government releases) as evidence and always shows both sides if something's disputed. It fact-checks the *claim*, never the outlet that ran it.
- **Tells you when it's fresh.** Push notifications the moment a new crisis report lands, shareable verdict cards for anything you want to send to a group chat, and a first-launch walkthrough that explains how the whole pipeline works before you start scrolling.

## Download

No Play Store listing yet — grab a build straight from GitHub instead:

1. Go to the [**Releases**](https://github.com/begoneeraj/Newsup/releases) page and download the latest `TruthLensIndia-*.apk`.
   - No release yet? Check [**Actions → Build & Release APK**](https://github.com/begoneeraj/Newsup/actions/workflows/release-apk.yml) — every run uploads the APK as a downloadable artifact even without a tagged release.
2. On your Android phone, allow "Install unknown apps" for whatever app you downloaded it with (Settings → Apps → *your browser/file manager* → Install unknown apps), then open the APK to install.
3. That's it — no Play Store account, no sideloading tools needed.

Want to trigger a fresh build yourself? Go to **Actions → Build & Release APK → Run workflow**. Push a tag like `v1.0.0` if you want it to show up as a proper GitHub Release instead of just a build artifact.

## How it's built

```
┌─────────────────────────────────────────────────────────────────┐
│  Sources (every 2–4 hours, via GitHub Actions cron)              │
│  Google News · NewsData.io · Mediastack · PIB/Hindu/IE/PRS/BBC   │
│  RSS · r/india · r/worldnews · crisis-hunting subreddits ·       │
│  Twitter (RSSHub) · YouTube transcripts                          │
└───────────────────────────┬───────────────────────────────────────┘
                            ▼
        Dedup: exact-hash check → pgvector semantic similarity
                            ▼
        Groq (Llama 3):
          · small/fast model   → routine fact-checks
          · large model        → crisis reports & claim-level
                                 legally-safe verification
                            ▼
                  Supabase (Postgres + pgvector)
                            ▼
                    Flutter app (Riverpod + go_router)
```

Crisis-hunting subreddits (JEE/NEET-specific) are the only source that skips straight to a crisis report — everything else starts as a routine fact-check and only becomes a bigger story if the evidence says so.

## Tech stack

| Layer | What's used |
|---|---|
| Backend pipeline | Python, asyncio, `aiohttp`, `feedparser` |
| AI | Groq (Llama 3.1 8B for routine checks, Llama 3.3 70B for crisis/claim analysis) |
| Database | Supabase (Postgres, pgvector, Row-Level Security, Storage) |
| Automation | GitHub Actions (cron ingestion + on-demand APK builds) |
| App | Flutter, Riverpod, go_router, Firebase Cloud Messaging |

## Project layout

```
src/                      Python ingestion pipeline
  fetchers/                News/social sources (Google News, NewsData, Mediastack, RSS, Reddit, YouTube, Twitter)
  ai_processor/            Groq prompts + embeddings for dedup
  database/                Supabase client, rate limiting, outlet credibility lookup
  models/                  Pydantic schemas shared with the Flutter models
  main.py                  Pipeline entry point

lib/src/                  Flutter app
  screens/                 Fact Checks, Crisis Tracker, onboarding
  widgets/                 Cards, share sheets, coverage/evidence sections
  providers/               Riverpod data providers
  services/                Supabase client wrapper

supabase/
  schema.sql               Base tables
  migrations/              Incremental schema changes, run in order
```

## Running it yourself

**Backend pipeline**
```bash
pip install -r requirements.txt
cp .env.example .env   # fill in your own keys
python src/main.py --sources news,reddit,social,youtube
```

You'll need your own keys for: Groq, Supabase (URL + service key), and optionally NewsData.io / Mediastack (both have free tiers). Run everything in `supabase/migrations/` in order against your own Supabase project before the first pipeline run.

**Flutter app**
```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_PUBLISHABLE_KEY=your_publishable_key
```

The publishable key is the safe-to-embed anon key from your Supabase project settings — never the service key.

---

Built as a student-accountability tool for Indian news — because the news cycle moves faster than the institutions it reports on.
