# GDELT Ingestion Pipeline — Production Readiness Review

Covers Phases 1–5 (`fetchGdeltArticles.ts`, `crisisClassifier.ts`, `src/api_server.py`, the Firestore composite index, and the Flutter `crisis_tracker_list_screen.dart` filter). Two items below are implemented in this pass (retry logic in `fetchGdeltArticles.ts`, verified live); the rest are commands/queries/design notes to run or wire up outside this repo.

---

## 1. Deployment order

```bash
# Step 1 — MUST complete before any code deploy
firebase deploy --only firestore:indexes

# Step 2
firebase deploy --only functions:fetchGdeltArticles

# Step 3
firebase deploy --only functions:crisisClassifier

# Step 4
# Flutter build/release (App Store Connect / Play Console / your CI)
```

**Why this order, specifically:**

- **Index builds are asynchronous and can take minutes to hours** on a collection with meaningful document count. `firestore:indexes` deploy *returns immediately* once the index is queued — it does not block until the index is `READY`. If you deploy functions or the client before the index finishes building, any query that needs it (`where('source_system', ...).orderBy('published_at', ...)`) throws `FAILED_PRECONDITION` until the build completes. That's exactly the error string `crisis_tracker_list_screen.dart`'s `StreamBuilder` now surfaces as "Index not ready — run: firebase deploy --only firestore:indexes" — so deploying the index last would guarantee that message appears in production for every user on the filtered segments, not just protect against it.
- **`fetchGdeltArticles` before `crisisClassifier`**: `crisisClassifier` triggers on `raw_articles` document creation. If it deploys first and somehow a document gets created before it exists (e.g. a manual test write), that document silently never gets classified — Firestore triggers don't retroactively fire for pre-existing documents. Deploying the writer first, then the trigger, means the trigger is live before any real documents exist.
- **Flutter last**: the client's Firestore queries must never run against an index that isn't `READY` yet, and the client shouldn't assume `raw_articles` has any documents in it until the backend functions have had at least one scheduled run. Shipping the client last means real users only ever see a working, populated feed — never a build in the "index not ready" or "empty collection" transitional state.
- Practically: after step 1, check index status before proceeding — `gcloud firestore indexes composite list` should show `state: READY` for the `raw_articles` (source_system ASC, published_at DESC) index before step 2.

---

## 2. Retry logic — implemented and verified

Added to `functions/src/fetchGdeltArticles.ts`. Two judgment calls worth flagging before the diff:

- **"Max 3 attempts" + three delay values (1s/2s/4s)** is ambiguous (3 total tries using 2 delays, vs. 3 retries after the initial try using all 3 delays). Implemented as **3 retries → 4 total attempts**, consuming all three delays — the more common convention when a backoff array has exactly as many entries as "max attempts." `RETRY_DELAYS_MS.length + 1` drives the loop, so trimming the array to `[1000, 2000]` gets you the other reading with a one-line change.
- **429 is treated as retryable**, despite being a 4xx and the spec saying "do NOT retry on 4xx." GDELT's own 429 body literally asks callers to back off and retry, and 429 has been *the* dominant transient failure observed against this live API throughout this project's testing. All other 4xx (400, 404, etc.) remain non-retryable exactly as specified — retrying an identical malformed/not-found request can't succeed. Revert by removing `|| res.status === 429` from the retryable check if you'd rather match the spec literally.

```typescript
const RETRY_DELAYS_MS = [1000, 2000, 4000];

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

type FetchAttemptResult =
  | { status: "success"; articles: RawArticle[] }
  | { status: "retryable"; reason: string }
  | { status: "fatal"; reason: string };

async function attemptGdeltFetch(url: string): Promise<FetchAttemptResult> {
  let res: Response;
  try {
    res = await fetch(url, { headers: { "User-Agent": "newsup-gdelt-ingest/1.0" } });
  } catch (err) {
    return { status: "retryable", reason: `network error: ${err instanceof Error ? err.message : String(err)}` };
  }

  if (!res.ok) {
    const bodySnippet = await res.text().catch(() => "");
    const isRetryable = res.status >= 500 || res.status === 429;
    return {
      status: isRetryable ? "retryable" : "fatal",
      reason: `HTTP ${res.status} ${res.statusText}: ${bodySnippet.slice(0, 300)}`,
    };
  }

  const contentType = res.headers.get("content-type") ?? "";
  const rawText = await res.text();

  if (!contentType.includes("application/json")) {
    // Deterministic config problem (e.g. "Timespan is too short."), not
    // transient -- retrying the identical request can't help.
    return { status: "fatal", reason: `non-JSON body on HTTP 200 (content-type: "${contentType || "none"}"): ${rawText.slice(0, 300)}` };
  }

  let data: unknown;
  try {
    data = JSON.parse(rawText);
  } catch (err) {
    return { status: "fatal", reason: `JSON.parse failed despite JSON content-type: ${err instanceof Error ? err.message : String(err)}` };
  }

  const articles = (data as { articles?: unknown }).articles;
  if (!Array.isArray(articles)) {
    return { status: "fatal", reason: "JSON body had no 'articles' array" };
  }

  return { status: "success", articles: articles as RawArticle[] };
}

async function fetchGdeltArticleList(): Promise<RawArticle[] | null> {
  const url = buildGdeltUrl();
  const maxAttempts = RETRY_DELAYS_MS.length + 1;
  let lastReason = "";

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (attempt > 1) {
      const delayMs = RETRY_DELAYS_MS[attempt - 2];
      logger.warn("Retrying GDELT fetch after a transient failure", { url, attempt, maxAttempts, delayMs, lastReason });
      await sleep(delayMs);
    }

    const result = await attemptGdeltFetch(url);
    if (result.status === "success") return result.articles;

    lastReason = result.reason;
    if (result.status === "fatal") {
      logger.error("GDELT fetch failed with a non-retryable error", { url, attempt, reason: result.reason });
      return null; // does not fail the function invocation
    }
    // "retryable" -- loop continues
  }

  logger.error("GDELT fetch exhausted all retries", { url, attempts: maxAttempts, lastReason });
  return null; // does not fail the function invocation
}
```

**Verified live**, not just written: a throwaway local HTTP server was scripted to (a) fail twice with 500 then succeed — confirmed 3 attempts, ~3.1s elapsed matching the 1s+2s backoff; (b) fail once with 404 — confirmed exactly 1 attempt, no retry; (c) fail with 429 on all attempts — confirmed all 4 attempts consumed before giving up. `tsc --noEmit` clean, all 19 existing Jest tests still pass after the change.

---

## 3. Billing alert

```bash
# 1. Find your billing account ID
gcloud billing accounts list

# 2. Create a $5/month budget scoped to this project
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="newsup-gdelt-pipeline-5usd" \
  --budget-amount=5USD \
  --filter-projects=projects/newsup-db01f \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 \
  --threshold-rule=percent=1.5
```

Notes on the command: `--filter-projects` scopes the budget to just this Firebase project (rather than the whole billing account, which may cover other projects) — use `projects/<PROJECT_ID>`, matching the project ID visible in `newsup-db01f-firebase-adminsdk-fbsvc-b01e8609a2.json` in this repo. The four threshold rules fire notifications (to billing-account admins by default, or a Pub/Sub topic if you wire one up) at 50%, 90%, 100%, and 150% of the $5 cap — 150% is included deliberately since Firestore/Functions costs can spike suddenly if something loops (e.g. a bug causing repeated retries), and you want a signal past "at budget" too.

**Cost breakdown — verified arithmetic, one real omission flagged:**

| Item | Calculation | Cost |
|---|---|---|
| Firestore writes | 100 records × 96 runs/day × $0.90/100k | **9,600/day → ~$0.086/day** |
| Firestore reads (ingestion) | Blind `.create()`, no query reads in `fetchGdeltArticles`/`crisisClassifier` | **$0** |
| Cloud Functions invocations | (96 `fetchGdeltArticles` + up to a few hundred `crisisClassifier` triggers)/day × $0.40/1M | **negligible** |
| **Backend subtotal** | $0.086/day × 30 | **~$2.60/month** |

The arithmetic checks out exactly as given (9,600 write-attempts/day ÷ 100,000 × $0.90 = $0.0864/day → ×30 ≈ $2.59/month). Firestore bills a write operation per `.create()` **call**, not per success — so duplicate-skipped documents (the ~75% overlap from the 60-minute-window/15-minute-schedule design) still cost a write op each, which is already folded into the "100 records × 96 runs" figure.

**What would push this higher — and one real gap in the original breakdown:**

1. **Cloud Functions compute time (GB-seconds), not just invocation count.** The breakdown above only counts the $0.40/1M invocation charge; Cloud Functions also bills for memory × duration. `fetchGdeltArticles` is provisioned at 256MiB with a 300s timeout — if GDELT is slow or the new retry logic hits its full backoff chain (up to ~7s of added latency per run, worst case), that's additional GB-seconds billed 96×/day. Still likely under $1/month at this scale, but it's a real line item the given breakdown omits entirely.
2. **Firestore reads from the Flutter client are the actual missing line item.** The breakdown above is ingestion-only. `crisis_tracker_list_screen.dart`'s new `StreamBuilder` opens a **live Firestore listener** per active app session — each listener is billed 1 read per document on initial snapshot plus 1 read per document on every subsequent update it receives while the listener is open. At meaningful user counts, this — not the ingestion pipeline — is very likely the dominant real-world cost, and scales with DAU × session length × document churn rate, not with GDELT's fetch cadence. This alone could blow past $5/month well before the ingestion side does, and isn't reflected in the "~$2.60/month base" figure at all.
3. Retries themselves add Firestore reads/writes only indirectly (more GDELT fetch attempts, not more Firestore ops) — the retry logic added in §2 doesn't change the write-cost math above.
4. A larger `GDELT_QUERY`/`maxrecords`, or a shorter schedule interval, directly multiplies the write count linearly.

---

## 4. Monitoring — Cloud Logging queries

All three assume the structured `logger.info("GDELT ingestion complete", {...})` / `logger.error(...)` calls already in `fetchGdeltArticles.ts`, using Cloud Logging's native JSON-payload field matching (`jsonPayload.<field>` — Firebase Functions v2's `logger` writes structured logs as JSON, not text, so these fields are queryable directly without regex).

**a) Invocations where `errors > 0`:**
```
resource.type="cloud_function"
resource.labels.function_name="fetchGdeltArticles"
jsonPayload.message="GDELT ingestion complete"
jsonPayload.errors>0
```

**b) Invocations where `duplicate_skips > 90`** (GDELT returning mostly already-seen articles — stale query window signal):
```
resource.type="cloud_function"
resource.labels.function_name="fetchGdeltArticles"
jsonPayload.message="GDELT ingestion complete"
jsonPayload.duplicate_skips>90
```

**c) Alert if `fetched === 0` for 3+ consecutive runs** (GDELT may be down): this one can't be expressed as a single Log Explorer filter, since "3 consecutive" requires comparing across log entries, not filtering within one. Two real ways to implement it:

- **Log-based metric + Cloud Monitoring alert policy** (recommended — no extra code): create a counter metric on the filter below, then an alerting policy with a rolling-window condition (e.g. "count ≥ 3 in the last 60 minutes", which at a 15-minute schedule realistically captures 3+ consecutive since a healthy run resets nothing in this metric — a genuinely correct "3 in a row" would need the metric to reset on a nonzero `fetched` too, which log-based metrics can't express, only an app-level check can, see below):
  ```
  resource.type="cloud_function"
  resource.labels.function_name="fetchGdeltArticles"
  jsonPayload.message="GDELT ingestion complete"
  jsonPayload.fetched=0
  ```
  ```bash
  gcloud logging metrics create gdelt_zero_fetch_runs \
    --description="GDELT ingestion runs that returned 0 articles" \
    --log-filter='resource.type="cloud_function" AND resource.labels.function_name="fetchGdeltArticles" AND jsonPayload.message="GDELT ingestion complete" AND jsonPayload.fetched=0'
  ```
  Then create an alerting policy on `logging.googleapis.com/user/gdelt_zero_fetch_runs` with a threshold of ≥3 over a 60-minute rolling window (4 scheduled runs fit in that window at 15-minute cadence, so 3+ zero-fetch runs within it is a reasonable proxy for "3 in a row," though not a strict guarantee if one nonzero run also lands in the same window).

- **Exact "3 consecutive" semantics** (if the log-metric approximation above isn't tight enough): track a `consecutive_zero_fetches` counter in a small Firestore doc (e.g. `_meta/gdelt_health`), incremented/reset inside `fetchGdeltArticles` itself on every run, and have the function call `logger.error("GDELT: 3+ consecutive zero-fetch runs", {...})` once the counter hits 3 — which then trivially becomes a Log Explorer alert on that exact error message. This is a small code change, not implemented in this pass since it wasn't asked for as code — flagging it here since the pure-Log-Explorer approach above is an approximation, not the literal "3 consecutive" the requirement describes.

---

## 5. GDELT tone upgrade path — design note

**Correcting an assumption in the task**: `api.gdeltproject.org/api/v2/gkg/...` does not exist as a per-article REST endpoint — confirmed live (`GET /api/v2/gkg/gkg` → `404`). This matches what was already documented in `crisisClassifier.ts`'s header comment from Phase 4: GDELT's Global Knowledge Graph (GKG) tone data is distributed only as **bulk CSV export files**, not queryable per-URL over REST. The design below reflects the real mechanism, not the REST-endpoint framing in the task.

**Mechanism:**
1. Poll `http://data.gdeltproject.org/gdeltv2/lastupdate.txt` — refreshed every 15 minutes, on the same cadence as the artlist fetch. It lists the URLs of the 3 latest bulk files (export, mentions, GKG).
2. Download and unzip the GKG file it points to (e.g. `http://data.gdeltproject.org/gdeltv2/20260709214500.gkg.csv.zip`) — typically tens of MB per 15-minute file, tab-delimited CSV, tens of thousands of rows.
3. Each row has a `DocumentIdentifier` column (the article URL) and a `V2Tone` column (comma-delimited; the first value is the average tone float, e.g. `-8.2,3.1,11.3,...`).

**Where in the pipeline this would slot in**: after the artlist fetch, before the Firestore write — i.e. inside (or as a step feeding into) `fetchGdeltArticles.ts`, not `crisisClassifier.ts`. The classifier only ever sees whatever `tone` value is already on the document by the time it's created; it has no ability to backfill real tone data itself without querying GKG per-document, which reintroduces the "no per-URL REST call exists" problem. Concretely: after `attemptGdeltFetch()` returns the artlist articles, a new step would download+parse that run's GKG file, build a `Map<url, tone>`, and `normalizeGdeltArticle()` would consume that map instead of hardcoding `tone: 0` — all before `writeArticle()` runs.

**Cost/complexity implication**: this is not "one extra API call per article" — GDELT gives no way to ask for a single article's tone directly. It's one bulk multi-MB download-and-parse **per ingestion run** (not per article), matched against however many artlist URLs came back that run via `DocumentIdentifier` string equality (fragile — redirects, AMP variants, and tracking-parameter differences between the artlist URL and the GKG URL will cause silent match misses). That's a meaningfully heavier function: more memory (parsing a large CSV), more execution time (likely blowing past a lean 256MiB/short-duration budget — probably needs its own function with higher memory, run on the same schedule, writing tone data keyed by URL hash so `fetchGdeltArticles` can look it up cheaply), and a new failure mode (GKG file unavailable/malformed) that doesn't currently exist.

**When this upgrade is actually worth it**: `applyToneHeuristic()` only fires when `tone !== 0`, and every GDELT document written today has `tone` hardcoded to `0` — so the heuristic is provably dead code in production right now, and will stay that way until this upgrade ships. It becomes worth the added cost/complexity specifically when there's evidence the tone-based confidence boost would meaningfully improve classification quality over relying on `classifyWithAiModel()` alone — e.g. after the crisis classifier has been running long enough to show cases where the AI model under-scores an article whose language is clearly severe/negative in a way tone would have caught. Building the GKG pipeline before there's evidence the signal is worth it would be optimizing a heuristic nobody has confirmed adds value yet.
