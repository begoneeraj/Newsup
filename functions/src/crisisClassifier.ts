// crisisClassifier.ts
//
// Firestore-triggered classifier: scores each newly ingested raw_articles
// document for crisis relevance/confidence.
//
// NOTE FOR REVIEWERS: this file did not previously exist in the functions/
// TypeScript package -- only fetchGdeltArticles.ts and utils/gdelt.ts do.
// classifyWithAiModel() below calls out to the existing Python Groq
// processor's HTTP endpoint (POST /classify, src/api_server.py) rather than
// reimplementing any classification logic in TS -- the "core AI
// classification logic" (the actual Groq prompt/model call) stays exactly
// where it already lived, in src/ai_processor/groq_processor.py. Everything
// in this file -- the trigger, the fetch wiring, the integration point, and
// applyToneHeuristic -- is real and tested.

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { defineString } from "firebase-functions/params";
import { FirestoreArticle } from "./utils/gdelt";

// GROQ_PROCESSOR_URL: base URL of the deployed src/api_server.py service,
// e.g. https://newsup-classifier-xxxxx.a.run.app (no trailing slash, no
// path -- "/classify" is appended below). Set via functions/.env(.local)
// for emulator use, or `firebase functions:secrets:set` / the deployed
// environment's config for production. See functions/.env.example.
const groqProcessorUrl = defineString("GROQ_PROCESSOR_URL");

// Optional: matches API_SHARED_SECRET on the Python side (src/api_server.py).
// Left empty, no X-API-Key header is sent -- fine if the Cloud Run service
// is already private (IAM-gated) rather than relying on a shared secret.
const groqProcessorApiKey = defineString("GROQ_PROCESSOR_API_KEY", {
  default: "",
});

interface ClassifyResponse {
  confidence: number;
  label: string;
}

// ---------------------------------------------------------------------------
// EXISTING CORE AI CLASSIFICATION LOGIC -- calls out to it, doesn't
// reimplement it. The actual model call lives in
// src/ai_processor/groq_processor.py:process_confidence_classification,
// behind src/api_server.py's POST /classify.
// ---------------------------------------------------------------------------
async function classifyWithAiModel(doc: FirestoreArticle): Promise<number> {
  const baseUrl = groqProcessorUrl.value();
  if (!baseUrl) {
    throw new Error("GROQ_PROCESSOR_URL is not configured");
  }

  const url = `${baseUrl.replace(/\/+$/, "")}/classify`;
  const apiKey = groqProcessorApiKey.value();

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (apiKey) {
    headers["X-API-Key"] = apiKey;
  }

  const res = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({
      title: doc?.title ?? "",
      url: doc?.url ?? "",
      summary: doc?.summary ?? "",
      content: doc?.content ?? "",
    }),
  });

  if (!res.ok) {
    const bodySnippet = await res.text().catch(() => "");
    throw new Error(
      `GROQ_PROCESSOR_URL returned HTTP ${res.status} ${res.statusText}: ${bodySnippet.slice(0, 300)}`
    );
  }

  const contentType = res.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new Error(
      `GROQ_PROCESSOR_URL returned a non-JSON response (content-type: "${contentType || "none"}")`
    );
  }

  const data = (await res.json()) as Partial<ClassifyResponse>;
  const confidence = Number(data.confidence);

  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 100) {
    throw new Error(
      `GROQ_PROCESSOR_URL returned an invalid confidence value: ${JSON.stringify(data.confidence)}`
    );
  }

  return confidence;
}

// ---------------------------------------------------------------------------
// WHY tone === 0 MEANS "NO DATA", NOT "NEUTRAL"
// ---------------------------------------------------------------------------
// This is critical context for future maintainers: do not "fix" this by
// treating tone === 0 as a legitimate neutral score.
//
// GDELT's artlist mode (mode=artlist) -- the only mode fetchGdeltArticles.ts
// calls -- never returns a "tone" field at all (confirmed via live testing
// in Phase 1). normalizeGdeltArticle() in utils/gdelt.ts hardcodes
// `tone: 0` for every GDELT-sourced document specifically because there is
// no real value to put there. Our own ingestion pipeline is the only writer
// of these documents, and it never computes or parses a real tone score --
// so tone === 0 on a source_system === "gdelt" doc is guaranteed, by
// construction, to be the placeholder default.
//
// This is NOT the same situation as a genuinely neutral article. GDELT's
// real tone metric (see the GKG note below) is a continuous float averaged
// over the article's sentiment-bearing words -- in practice it essentially
// never lands on exactly 0.0 for real articles. If this pipeline is later
// extended to populate real tone data (see below) and a genuinely neutral
// article scores exactly 0.0, this heuristic will silently (and
// incorrectly) treat it as "no data" and skip the boost. That's an
// acceptable tradeoff today because it's the ONLY way to distinguish
// "we have no data" from "the model said neutral" without adding a
// separate has_real_tone boolean field -- which would be the correct fix
// if/when real tone data is wired in.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// FUTURE EXTENSION: getting REAL tone data from GDELT's GKG API
// ---------------------------------------------------------------------------
// The DOC 2.0 API artlist mode used by fetchGdeltArticles.ts never returns
// tone, and mode=tonechart only returns an aggregate histogram across all
// matching articles, not a per-article score. Real per-article tone comes
// from GDELT's Global Knowledge Graph (GKG) 2.1 bulk export files, not a
// simple per-article REST call:
//
//   1. Poll http://data.gdeltproject.org/gdeltv2/lastupdate.txt every 15
//      minutes -- it lists the URLs of the 3 latest bulk files (export,
//      mentions, gkg), refreshed on the same 15-minute cadence as artlist.
//   2. Download and unzip the *.gkg.csv.zip file it points to, e.g.:
//      http://data.gdeltproject.org/gdeltv2/20260709214500.gkg.csv.zip
//   3. Parse the tab-delimited CSV. Each row has a `DocumentIdentifier`
//      column (the article URL -- matches the `url` field this pipeline
//      already stores) and a `V2Tone` column: a comma-delimited string
//      whose FIRST value is the average tone, e.g. "-8.2,3.1,11.3,...".
//   4. Match GKG rows to already-ingested raw_articles docs by URL and
//      backfill the real tone value (replacing the 0 default), then flip a
//      has_real_tone: true flag so this heuristic can distinguish "real
//      neutral" from "no data" instead of relying on tone !== 0.
//
// This is a nontrivial ETL addition (multi-MB CSV parsing per run, fuzzy
// URL matching against redirects/AMP variants) -- realistically a separate
// scheduled function, not a one-line change to the existing artlist fetch.
// Until it exists, applyToneHeuristic below will essentially never fire in
// production, because every GDELT doc it sees will have tone === 0.
// ---------------------------------------------------------------------------

const TONE_BOOST_CAP = 30;
const TONE_THRESHOLD = -5;
const SCORE_CAP = 100;

/**
 * Boosts an AI-derived base confidence score using GDELT's tone signal,
 * when (and only when) real tone data is actually available. See the
 * comment blocks above for why tone === 0 is treated as "no data" rather
 * than "neutral", and what it would take to make this heuristic actually
 * fire in practice.
 */
export function applyToneHeuristic(
  baseScore: number,
  doc: FirestoreArticle
): number {
  if (doc.source_system !== "gdelt") {
    return baseScore;
  }

  if (doc.tone === 0) {
    // The artlist default -- no real tone data was available. Not neutral.
    return baseScore;
  }

  if (doc.tone > TONE_THRESHOLD) {
    return baseScore;
  }

  const severityMultiplier = Math.abs(doc.tone) / 10;
  const boost = Math.min(TONE_BOOST_CAP, severityMultiplier * 30);

  return Math.min(SCORE_CAP, baseScore + boost);
}

export const crisisClassifier = onDocumentCreated(
  "raw_articles/{articleId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.error("crisisClassifier triggered with no document snapshot", {
        articleId: event.params.articleId,
      });
      return;
    }

    const doc = snapshot.data() as FirestoreArticle;

    let baseScore: number;
    try {
      baseScore = await classifyWithAiModel(doc);
    } catch (err) {
      logger.error("AI classification failed", {
        articleId: event.params.articleId,
        url: doc?.url,
        error: err instanceof Error ? err.message : String(err),
      });
      return;
    }

    // --- Integration point: tone heuristic applied on top of the
    // unmodified base AI score, never in place of it. ---
    const finalScore = applyToneHeuristic(baseScore, doc);

    await snapshot.ref.update({
      confidence_score: finalScore,
      base_confidence_score: baseScore,
      classified_at: new Date().toISOString(),
    });

    logger.info("Article classified", {
      articleId: event.params.articleId,
      baseScore,
      finalScore,
      toneHeuristicApplied: finalScore !== baseScore,
    });
  }
);
