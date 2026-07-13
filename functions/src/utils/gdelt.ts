// gdelt.ts (production)
// Pure utility module (no Firebase imports) that normalizes raw GDELT
// artlist JSON into the typed Firestore document schema this app writes.
//
// Confirmed live from the GDELT 2.0 Doc API (mode=artlist):
// - Only these fields are ever present: url, url_mobile, title, seendate,
//   socialimage, domain, language, sourcecountry.
// - tone, latitude, longitude are NEVER present in artlist output. Do not
//   assume they exist -- they default to 0 / null respectively.
// - seendate is YYYYMMDDTHHMMSSZ (no dashes, no colons), e.g. 20260709T214459Z.
// - timespan=15MIN gets rejected by the live API ("Timespan is too short.");
//   the fetch layer that calls this module must use 60min or larger. Not
//   this module's concern, but documented here since it bit us once.

export interface RawArticle {
  url: string;
  url_mobile: string;
  title: string;
  seendate: string;
  socialimage: string;
  domain: string;
  language: string;
  sourcecountry: string;
}

export interface FirestoreArticle {
  title: string;
  url: string;
  published_at: string; // ISO-8601
  summary: string; // always "" for GDELT articles
  content: string; // always ""
  source: string; // domain
  language: string;
  country: string; // sourcecountry
  tone: number; // default 0 -- artlist doesn't provide this
  latitude: number | null; // always null for artlist
  longitude: number | null; // always null for artlist
  source_system: "gdelt";
  ingested_at: string; // ISO-8601, now() at normalization time
}

// Matches the standard format (T present): 20260709T214459Z
// and the malformed variant (T missing/dropped): 20260709214459Z
const SEENDATE_PATTERN = /^(\d{4})(\d{2})(\d{2})T?(\d{2})(\d{2})(\d{2})Z$/;

/**
 * Parses a GDELT "seendate" string into an ISO-8601 string using plain
 * substring/regex slicing -- never Date.parse()/new Date(str). Never throws:
 * falls back to the current time if the input is unrecognizable or absent,
 * regardless of what the caller actually passes at runtime.
 */
export function parseSeendate(raw: string): string {
  if (typeof raw !== "string") {
    return new Date().toISOString();
  }

  const match = SEENDATE_PATTERN.exec(raw.trim());
  if (!match) {
    return new Date().toISOString();
  }

  const [, year, month, day, hour, minute, second] = match;

  const mo = Number(month);
  const d = Number(day);
  const h = Number(hour);
  const mi = Number(minute);
  const s = Number(second);

  const validRanges =
    mo >= 1 && mo <= 12 &&
    d >= 1 && d <= 31 &&
    h >= 0 && h <= 23 &&
    mi >= 0 && mi <= 59 &&
    s >= 0 && s <= 60; // allow leap second

  if (!validRanges) {
    return new Date().toISOString();
  }

  return `${year}-${month}-${day}T${hour}:${minute}:${second}Z`;
}

/**
 * Normalizes a raw GDELT artlist article into the Firestore document shape.
 * Never throws, even if `raw` is null/undefined/partially malformed at
 * runtime despite its declared type -- GDELT's own schema has already
 * surprised us once (see the header comment), so this stays defensive.
 */
export function normalizeGdeltArticle(raw: RawArticle): FirestoreArticle {
  try {
    const safe: Partial<RawArticle> & { tone?: unknown } = raw ?? {};

    const toneNumber = Number(safe?.tone);

    return {
      title: safe?.title ?? "",
      url: safe?.url ?? "",
      published_at: parseSeendate(safe?.seendate as string),
      summary: "",
      content: "",
      source: safe?.domain ?? "",
      language: safe?.language ?? "",
      country: safe?.sourcecountry ?? "",
      tone: Number.isFinite(toneNumber) ? toneNumber : 0,
      latitude: null,
      longitude: null,
      source_system: "gdelt",
      ingested_at: new Date().toISOString(),
    };
  } catch {
    return {
      title: "",
      url: "",
      published_at: new Date().toISOString(),
      summary: "",
      content: "",
      source: "",
      language: "",
      country: "",
      tone: 0,
      latitude: null,
      longitude: null,
      source_system: "gdelt",
      ingested_at: new Date().toISOString(),
    };
  }
}
