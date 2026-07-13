import { parseSeendate, normalizeGdeltArticle, RawArticle } from "./gdelt";

const ISO_8601_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

describe("parseSeendate", () => {
  it("parses the standard YYYYMMDDTHHMMSSZ format", () => {
    expect(parseSeendate("20260709T214459Z")).toBe("2026-07-09T21:44:59Z");
  });

  it("parses the malformed variant with the T dropped", () => {
    expect(parseSeendate("20260709214459Z")).toBe("2026-07-09T21:44:59Z");
  });

  it("falls back to now() for a completely missing seendate", () => {
    const before = Date.now();
    // @ts-expect-error intentionally violating the declared (string) type
    const result = parseSeendate(undefined);
    const after = Date.now();

    expect(result).toMatch(ISO_8601_RE);
    const resultMs = new Date(result).getTime();
    expect(resultMs).toBeGreaterThanOrEqual(before);
    expect(resultMs).toBeLessThanOrEqual(after);
  });

  it("falls back to now() for null", () => {
    // @ts-expect-error intentionally violating the declared (string) type
    expect(parseSeendate(null)).toMatch(ISO_8601_RE);
  });

  it("falls back to now() for garbage input", () => {
    expect(parseSeendate("not-a-date")).toMatch(ISO_8601_RE);
  });

  it("falls back to now() for out-of-range components", () => {
    expect(parseSeendate("20261309T214459Z")).toMatch(ISO_8601_RE); // month 13
  });

  it("never throws regardless of input type", () => {
    // @ts-expect-error intentionally passing a non-string at runtime
    expect(() => parseSeendate(12345)).not.toThrow();
    // @ts-expect-error intentionally passing an object at runtime
    expect(() => parseSeendate({})).not.toThrow();
  });
});

describe("normalizeGdeltArticle", () => {
  const fullArticle: RawArticle = {
    url: "https://example.com/article",
    url_mobile: "https://example.com/article?amp",
    title: "Earthquake Strikes Region",
    seendate: "20260709T214459Z",
    socialimage: "https://example.com/img.jpg",
    domain: "example.com",
    language: "English",
    sourcecountry: "United States",
  };

  it("normalizes a complete article correctly", () => {
    const result = normalizeGdeltArticle(fullArticle);

    expect(result).toEqual({
      title: "Earthquake Strikes Region",
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
      ingested_at: expect.stringMatching(ISO_8601_RE),
    });
  });

  it("handles a malformed seendate (missing T) inside a full article", () => {
    const result = normalizeGdeltArticle({
      ...fullArticle,
      seendate: "20260709214459Z",
    });

    expect(result.published_at).toBe("2026-07-09T21:44:59Z");
  });

  it("handles a completely missing seendate", () => {
    const { seendate, ...withoutSeendate } = fullArticle;
    const result = normalizeGdeltArticle(withoutSeendate as RawArticle);

    expect(result.published_at).toMatch(ISO_8601_RE);
  });

  it("defaults every field when the article has nothing at all", () => {
    const result = normalizeGdeltArticle({} as RawArticle);

    expect(result.title).toBe("");
    expect(result.url).toBe("");
    expect(result.summary).toBe("");
    expect(result.content).toBe("");
    expect(result.source).toBe("");
    expect(result.language).toBe("");
    expect(result.country).toBe("");
    expect(result.tone).toBe(0);
    expect(result.latitude).toBeNull();
    expect(result.longitude).toBeNull();
    expect(result.source_system).toBe("gdelt");
    expect(result.published_at).toMatch(ISO_8601_RE);
    expect(result.ingested_at).toMatch(ISO_8601_RE);
  });

  it("never throws even when raw is null/undefined at runtime", () => {
    // @ts-expect-error intentionally violating the declared type
    expect(() => normalizeGdeltArticle(null)).not.toThrow();
    // @ts-expect-error intentionally violating the declared type
    expect(() => normalizeGdeltArticle(undefined)).not.toThrow();
  });

  it("never throws for a totally malformed raw object", () => {
    // @ts-expect-error intentionally violating the declared type
    expect(() => normalizeGdeltArticle("not an object")).not.toThrow();
    // @ts-expect-error intentionally violating the declared type
    expect(() => normalizeGdeltArticle(42)).not.toThrow();
  });
});
