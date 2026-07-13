import { applyToneHeuristic } from "./crisisClassifier";
import { FirestoreArticle } from "./utils/gdelt";

function makeArticle(overrides: Partial<FirestoreArticle> = {}): FirestoreArticle {
  return {
    title: "Test article",
    url: "https://example.com/article",
    published_at: "2026-07-09T21:44:59Z",
    summary: "",
    content: "",
    source: "example.com",
    language: "English",
    country: "United States",
    tone: 0,
    latitude: null,
    longitude: null,
    source_system: "gdelt",
    ingested_at: "2026-07-09T21:45:00Z",
    ...overrides,
  };
}

describe("applyToneHeuristic", () => {
  it("skips the boost for a non-GDELT (e.g. newsapi) article", () => {
    const doc = {
      ...makeArticle({ tone: -10 }),
      source_system: "newsapi" as unknown as "gdelt",
    };

    expect(applyToneHeuristic(50, doc)).toBe(50);
  });

  it("skips the boost for a GDELT article with tone === 0 (artlist default)", () => {
    const doc = makeArticle({ tone: 0 });

    expect(applyToneHeuristic(50, doc)).toBe(50);
  });

  it("skips the boost for a GDELT article with tone above the threshold (-3)", () => {
    const doc = makeArticle({ tone: -3 });

    expect(applyToneHeuristic(50, doc)).toBe(50);
  });

  it("applies the boost for a GDELT article with real tone data below the threshold (-7)", () => {
    const doc = makeArticle({ tone: -7 });

    // severityMultiplier = 0.7, boost = 21
    expect(applyToneHeuristic(50, doc)).toBe(71);
  });

  it("caps the final score at 100 for tone === -10 and baseScore 80", () => {
    const doc = makeArticle({ tone: -10 });

    // severityMultiplier = 1.0, boost = 30, 80 + 30 = 110 -> capped at 100
    expect(applyToneHeuristic(80, doc)).toBe(100);
  });

  it("applies the boost at the exact boundary (tone === -5)", () => {
    const doc = makeArticle({ tone: -5 });

    // severityMultiplier = 0.5, boost = 15
    expect(applyToneHeuristic(50, doc)).toBe(65);
  });
});
