// fetchGdeltArticles.ts
//
// Firestore composite index required by the Flutter client (query:
// where('source_system', '==', 'gdelt').orderBy('published_at', 'desc')).
// Merge this entry into firestore.indexes.json at the repo root:
//
// {
//   "indexes": [
//     {
//       "collectionGroup": "raw_articles",
//       "queryScope": "COLLECTION",
//       "fields": [
//         { "fieldPath": "source_system", "order": "ASCENDING" },
//         { "fieldPath": "published_at", "order": "DESCENDING" }
//       ]
//     }
//   ],
//   "fieldOverrides": []
// }
//
// ---------------------------------------------------------------------------
// KNOWN GDELT API DISCREPANCY (confirmed via live testing in Phase 1):
// timespan=15MIN is REJECTED by the live API -- it returns HTTP 200 (not an
// error status) with a plain-text body "Timespan is too short.", not JSON.
// The smallest value that reliably returned JSON during testing was 60min.
// This function is scheduled every 15 minutes but fetches a 60-minute
// window on each run; the resulting ~75% overlap between consecutive runs
// is intentional and absorbed by the SHA-256(url) blind-write dedup below,
// not a bug. GDELT_TIMESPAN is a top-level const specifically so this can
// be revisited if GDELT's minimum-timespan behavior changes.
// ---------------------------------------------------------------------------

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { createHash } from "crypto";
import { normalizeGdeltArticle, RawArticle } from "./utils/gdelt";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const GDELT_URL = "https://api.gdeltproject.org/api/v2/doc/doc";

const GDELT_QUERY =
  "earthquake OR flood OR wildfire OR cyclone OR hurricane OR protest OR riot OR " +
  "strike OR war OR military OR election OR epidemic OR pandemic OR explosion OR corruption";

// See the discrepancy note above -- 15MIN is rejected by the live API.
const GDELT_TIMESPAN = "60min";

const RAW_ARTICLES_COLLECTION = "raw_articles";

// gRPC status code for ALREADY_EXISTS. Firestore's Node SDK surfaces this on
// error.code when .create() targets a document ID that already exists.
const FIRESTORE_ALREADY_EXISTS = 6;

function buildGdeltUrl(): string {
  const params = new URLSearchParams({
    query: GDELT_QUERY,
    mode: "artlist",
    format: "json",
    timespan: GDELT_TIMESPAN,
    maxrecords: "100",
    sort: "datedesc",
  });
  return `${GDELT_URL}?${params.toString()}`;
}

// ---------------------------------------------------------------------------
// RETRY / BACKOFF CONFIG (Phase 6 hardening)
//
// "Max 3 attempts" + three explicit delay values (1s/2s/4s) is read here as
// 3 RETRIES after the initial try (4 total attempts), consuming all three
// delays -- the more common convention for a length-3 backoff array. If you
// meant 3 total tries instead, drop RETRY_DELAYS_MS to [1000, 2000] and this
// still works unchanged (the loop is driven by the array's length, not a
// separate count).
//
// Deliberate narrowing of "do NOT retry on 4xx": 429 (rate limit) is treated
// as retryable despite being a 4xx. GDELT's own 429 body explicitly asks
// callers to back off and retry ("Please limit requests to one every 5
// seconds..."), and 429 has been, empirically, the single most common
// transient failure against this API. Every other 4xx (400/404/etc.) stays
// non-retryable exactly as specified -- retrying an identical malformed
// request can't succeed. A non-JSON HTTP 200 body (e.g. GDELT's "Timespan
// is too short.") is also treated as non-retryable for the same reason: a
// deterministic config problem, not a transient one.
// ---------------------------------------------------------------------------
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
    res = await fetch(url, {
      headers: { "User-Agent": "newsup-gdelt-ingest/1.0" },
    });
  } catch (err) {
    return {
      status: "retryable",
      reason: `network error: ${err instanceof Error ? err.message : String(err)}`,
    };
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

  // GDELT can return HTTP 200 with a plain-text error body (e.g. "Timespan
  // is too short."). Never assume 200 means JSON -- gate on Content-Type
  // before attempting to parse.
  if (!contentType.includes("application/json")) {
    return {
      status: "fatal",
      reason: `non-JSON body on HTTP 200 (content-type: "${contentType || "none"}"): ${rawText.slice(0, 300)}`,
    };
  }

  let data: unknown;
  try {
    data = JSON.parse(rawText);
  } catch (err) {
    return {
      status: "fatal",
      reason: `JSON.parse failed despite JSON content-type: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  const articles = (data as { articles?: unknown }).articles;
  if (!Array.isArray(articles)) {
    return { status: "fatal", reason: "JSON body had no 'articles' array" };
  }

  return { status: "success", articles: articles as RawArticle[] };
}

/**
 * Fetches and parses the GDELT artlist response, retrying transient
 * failures (network errors, 5xx, 429) with exponential backoff. Never
 * throws -- exhausting all retries, or hitting a non-retryable failure,
 * is logged as a structured error and results in `null`, which the caller
 * treats as "nothing to ingest this run" without failing the invocation.
 */
async function fetchGdeltArticleList(): Promise<RawArticle[] | null> {
  const url = buildGdeltUrl();
  const maxAttempts = RETRY_DELAYS_MS.length + 1;

  let lastReason = "";

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (attempt > 1) {
      const delayMs = RETRY_DELAYS_MS[attempt - 2];
      logger.warn("Retrying GDELT fetch after a transient failure", {
        url,
        attempt,
        maxAttempts,
        delayMs,
        lastReason,
      });
      await sleep(delayMs);
    }

    const result = await attemptGdeltFetch(url);

    if (result.status === "success") {
      return result.articles;
    }

    lastReason = result.reason;

    if (result.status === "fatal") {
      logger.error("GDELT fetch failed with a non-retryable error", {
        url,
        attempt,
        reason: result.reason,
      });
      return null;
    }

    // status === "retryable" -- loop continues.
  }

  logger.error("GDELT fetch exhausted all retries", {
    url,
    attempts: maxAttempts,
    lastReason,
  });
  return null;
}

type WriteOutcome = "inserted" | "duplicate" | "error";

/**
 * Blind-writes a single normalized article using SHA-256(url) as the
 * Firestore document ID, so re-fetching the same article across
 * overlapping 15-minute runs is a safe, idempotent no-op rather than a
 * duplicate row. Never throws -- every failure mode resolves to a
 * WriteOutcome so Promise.allSettled always sees "fulfilled".
 */
async function writeArticle(
  db: FirebaseFirestore.Firestore,
  raw: RawArticle
): Promise<WriteOutcome> {
  const normalized = normalizeGdeltArticle(raw);

  // raw?.url may be missing/malformed despite RawArticle declaring it
  // required -- GDELT's live schema has surprised us before. An empty
  // string still hashes deterministically, which just means malformed
  // articles collide with each other as duplicate_skips rather than being
  // written under distinct IDs, which is an acceptable degenerate case.
  const hash = createHash("sha256").update(raw?.url ?? "").digest("hex");

  try {
    await db.collection(RAW_ARTICLES_COLLECTION).doc(hash).create(normalized);
    return "inserted";
  } catch (err) {
    const code = (err as { code?: number })?.code;
    if (code === FIRESTORE_ALREADY_EXISTS) {
      return "duplicate";
    }

    logger.error("Failed to write GDELT article to Firestore", {
      url: raw?.url,
      error: err instanceof Error ? err.message : String(err),
    });
    return "error";
  }
}

export const fetchGdeltArticles = onSchedule(
  {
    schedule: "every 15 minutes",
    memory: "256MiB",
    timeoutSeconds: 300,
    // Node.js 18 runtime is set via functions/package.json's
    // "engines": { "node": "18" } (configured in Phase 2) -- onSchedule's
    // v2 options have no per-function "runtime" field to set here.
  },
  async () => {
    const startedAt = Date.now();

    const articles = await fetchGdeltArticleList();
    if (articles === null) {
      // Already logged in fetchGdeltArticleList. Return early without
      // crashing -- there is nothing to ingest this run.
      return;
    }

    const fetched = articles.length;

    if (fetched === 0) {
      logger.info("GDELT ingestion complete", {
        fetched: 0,
        inserted: 0,
        duplicate_skips: 0,
        errors: 0,
        duration_ms: Date.now() - startedAt,
      });
      return;
    }

    const db = admin.firestore();

    // Promise.allSettled, not for...of + await: one slow/failed write must
    // never block the rest. writeArticle() itself never rejects, but
    // allSettled is used regardless per spec, as a defensive outer layer.
    const results = await Promise.allSettled(
      articles.map((raw) => writeArticle(db, raw))
    );

    let inserted = 0;
    let duplicate_skips = 0;
    let errors = 0;

    for (const result of results) {
      if (result.status === "fulfilled") {
        if (result.value === "inserted") inserted++;
        else if (result.value === "duplicate") duplicate_skips++;
        else errors++;
      } else {
        // Should be unreachable since writeArticle() catches internally,
        // but counted as an error rather than silently dropped.
        errors++;
      }
    }

    logger.info("GDELT ingestion complete", {
      fetched,
      inserted,
      duplicate_skips,
      errors,
      duration_ms: Date.now() - startedAt,
    });
  }
);
