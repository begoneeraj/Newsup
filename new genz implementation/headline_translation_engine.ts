/**
 * HEADLINE TRANSLATION ENGINE
 * Automatically translates formal news headlines to Gen Z speak
 * Uses pattern matching + AI fallback for best results
 */

import Redis from "redis";
import Anthropic from "@anthropic-ai/sdk";

const redis = Redis.createClient({
  host: process.env.REDIS_HOST || "localhost",
  port: parseInt(process.env.REDIS_PORT || "6379"),
});

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// ============================================
// PART 1: LOAD SLANG DICTIONARY
// ============================================

interface SlangTerm {
  slang: string;
  formal: string[];
  context: string;
  usage_probability: number;
  emoji?: string;
}

interface SlangDictionary {
  [category: string]: SlangTerm[];
}

const slangDictionary: SlangDictionary = {
  truth_and_lies: [
    { slang: "cap", formal: ["lie", "false", "fake"], context: "false", usage_probability: 0.95, emoji: "🧢" },
    { slang: "no cap", formal: ["for real", "honestly", "truly"], context: "truthful", usage_probability: 0.90, emoji: "✅" },
    { slang: "sus", formal: ["suspicious", "questionable", "sketchy"], context: "questionable", usage_probability: 0.88, emoji: "🤨" },
    { slang: "caught in 4K", formal: ["caught red-handed", "proven", "evidence"], context: "proven wrong", usage_probability: 0.75, emoji: "📷" },
  ],
  quality_assessment: [
    { slang: "slaps", formal: ["great", "amazing", "awesome"], context: "good", usage_probability: 0.85, emoji: "🔥" },
    { slang: "bussin", formal: ["excellent", "amazing"], context: "really good", usage_probability: 0.82, emoji: "👌" },
    { slang: "slay", formal: ["succeed", "crush it", "excel"], context: "doing well", usage_probability: 0.87, emoji: "⚔️" },
    { slang: "ate", formal: ["crushed it", "succeeded", "perfect"], context: "perfect execution", usage_probability: 0.83, emoji: "🍽️" },
    { slang: "cooked", formal: ["tired", "exhausted", "ruined"], context: "tired/in trouble", usage_probability: 0.79, emoji: "🍳" },
    { slang: "mid", formal: ["mediocre", "average", "boring"], context: "mediocre", usage_probability: 0.81, emoji: "😐" },
    { slang: "wild", formal: ["crazy", "insane", "unbelievable"], context: "shocking", usage_probability: 0.84, emoji: "🤪" },
    { slang: "major L", formal: ["loss", "failure", "mistake"], context: "failure", usage_probability: 0.77, emoji: "❌" },
    { slang: "W move", formal: ["win", "good decision", "smart"], context: "success", usage_probability: 0.78, emoji: "✅" },
  ],
  personal_reference: [
    { slang: "bro", formal: ["brother", "guy", "man"], context: "address", usage_probability: 0.95, emoji: "🤖" },
    { slang: "twin", formal: ["best friend", "close friend"], context: "close friend", usage_probability: 0.85, emoji: "👯‍♂️" },
    { slang: "gng", formal: ["friend", "person", "homie"], context: "person", usage_probability: 0.80, emoji: "👥" },
    { slang: "fynshit", formal: ["beautiful", "gorgeous", "stunning"], context: "attractive", usage_probability: 0.80, emoji: "✨" },
  ],
  emphasis: [
    { slang: "fr", formal: ["for real", "really", "truly"], context: "emphasis", usage_probability: 0.92, emoji: "💯" },
    { slang: "nahhh", formal: ["no", "nope", "absolutely not"], context: "disagreement", usage_probability: 0.83, emoji: "🙅" },
    { slang: "lowkey", formal: ["sort of", "kind of", "somewhat"], context: "subtle", usage_probability: 0.89, emoji: "🤐" },
  ],
};

// ============================================
// PART 2: WORD MATCHING ENGINE
// ============================================

class WordMatcher {
  private dictionary: SlangDictionary;

  constructor(dict: SlangDictionary) {
    this.dictionary = dict;
  }

  /**
   * Find slang replacements in headline text
   */
  findMatches(text: string): Array<{ formal: string; slang: string; emoji?: string }> {
    const matches: Array<{ formal: string; slang: string; emoji?: string }> = [];
    const lowerText = text.toLowerCase();

    Object.values(this.dictionary).forEach((terms) => {
      terms.forEach((term) => {
        // Check each formal variant
        term.formal.forEach((formalWord) => {
          // Exact word matching (avoid partial matches)
          const regex = new RegExp(`\\b${formalWord}\\b`, "gi");
          if (regex.test(lowerText)) {
            matches.push({
              formal: formalWord,
              slang: term.slang,
              emoji: term.emoji,
            });
          }
        });
      });
    });

    return matches;
  }

  /**
   * Apply replacements to headline
   */
  replaceWords(text: string, matches: Array<{ formal: string; slang: string }>): string {
    let result = text;

    matches.forEach(({ formal, slang }) => {
      const regex = new RegExp(`\\b${formal}\\b`, "gi");
      result = result.replace(regex, slang);
    });

    return result;
  }
}

// ============================================
// PART 3: CONTEXT ANALYZER
// ============================================

class ContextAnalyzer {
  /**
   * Analyze headline context to determine tone
   */
  analyzeContext(headline: string): {
    tone: "funny" | "serious" | "shocking" | "sad" | "inspiring";
    keywords: string[];
    urgency: "breaking" | "developing" | "update" | "historical";
  } {
    const text = headline.toLowerCase();

    // Detect tone
    const funnyKeywords = ["banned", "exposed", "caught", "failed", "scandal"];
    const seriousKeywords = ["government", "court", "policy", "law", "official"];
    const shockingKeywords = ["death", "attack", "explosion", "crash", "disaster"];
    const sadKeywords = ["died", "loss", "tragedy", "accident", "victim"];
    const inspiringKeywords = ["saved", "helped", "donated", "awarded", "hero"];

    let tone: "funny" | "serious" | "shocking" | "sad" | "inspiring" = "serious";
    if (funnyKeywords.some((kw) => text.includes(kw))) tone = "funny";
    else if (shockingKeywords.some((kw) => text.includes(kw))) tone = "shocking";
    else if (sadKeywords.some((kw) => text.includes(kw))) tone = "sad";
    else if (inspiringKeywords.some((kw) => text.includes(kw))) tone = "inspiring";

    // Detect urgency
    let urgency: "breaking" | "developing" | "update" | "historical" = "update";
    if (text.includes("breaking") || text.includes("just") || text.includes("now")) urgency = "breaking";
    else if (text.includes("developing") || text.includes("developing")) urgency = "developing";
    else if (text.includes("revealed") || text.includes("announced")) urgency = "update";

    return {
      tone,
      keywords: headline.split(" ").slice(0, 5), // First 5 words
      urgency,
    };
  }

  /**
   * Check if headline is suitable for sarcastic tone
   */
  canBeSarcastic(headline: string): boolean {
    const unsuitableKeywords = ["death", "died", "murder", "rape", "abuse", "suicide"];
    const text = headline.toLowerCase();
    return !unsuitableKeywords.some((kw) => text.includes(kw));
  }
}

// ============================================
// PART 4: HEADLINE TRANSLATION SERVICE
// ============================================

interface TranslationResult {
  official: string;
  genZ: string;
  confidence: number;
  method: "rule_based" | "ai_generated";
  replacements: Array<{ original: string; replacement: string }>;
  emoji: string;
}

class HeadlineTranslator {
  private matcher: WordMatcher;
  private analyzer: ContextAnalyzer;
  private anthropic: typeof Anthropic;

  constructor(dict: SlangDictionary) {
    this.matcher = new WordMatcher(dict);
    this.analyzer = new ContextAnalyzer();
    this.anthropic = anthropic;
  }

  /**
   * Main translation method
   */
  async translate(headline: string): Promise<TranslationResult> {
    // 1. Check cache
    const cached = await this.getFromCache(headline);
    if (cached) {
      return {
        ...cached,
        method: "rule_based",
        confidence: 0.95,
      };
    }

    // 2. Try rule-based approach first
    const matches = this.matcher.findMatches(headline);
    if (matches.length > 0) {
      const translated = this.matcher.replaceWords(headline, matches);
      const context = this.analyzer.analyzeContext(headline);

      if (this.analyzer.canBeSarcastic(headline)) {
        const result: TranslationResult = {
          official: headline,
          genZ: translated,
          confidence: 0.75,
          method: "rule_based",
          replacements: matches.map((m) => ({
            original: m.formal,
            replacement: m.slang,
          })),
          emoji: matches[0]?.emoji || "💀",
        };

        // Cache it
        await this.saveToCache(headline, result);
        return result;
      }
    }

    // 3. Fallback to AI if rule-based didn't work well
    const aiTranslation = await this.generateWithAI(headline);

    // Cache it
    await this.saveToCache(headline, aiTranslation);

    return aiTranslation;
  }

  /**
   * Generate translation using Claude API
   */
  private async generateWithAI(headline: string): Promise<TranslationResult> {
    try {
      const context = this.analyzer.analyzeContext(headline);

      const systemPrompt = `You are a Gen Z translator. Convert formal news headlines to sarcastic, funny Gen Z speak in ONE SHORT LINE (max 15 words).

RULES:
- Use ONLY these safe slang words: cap, sus, no cap, fr, bro, twin, slay, bussin, cooked, mid, wild, nahhh, lowkey, highkey, 💀 😭 🔥 🤯 👀
- Keep it SHORT (under 15 words)
- Add 1-2 emojis MAX
- Be funny and relatable, not offensive
- Don't sound robotic
- Maintain that this is a NEWS app (still trustworthy)
- Context: ${context.tone} tone, ${context.urgency}

Example transformations:
"NTA exposed fake Telegram channels" → "Bro really thought he was slick 💀"
"30 students caught cheating" → "Caught in 4K fr fr 😭"
"Government released AI policy" → "AI just got new house rules no cap 🔥"`;

      const response = await this.anthropic.messages.create({
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 50,
        messages: [
          {
            role: "user",
            content: `Translate this headline:\n"${headline}"`,
          },
        ],
        system: systemPrompt,
      });

      const genZText = response.content[0].type === "text" ? response.content[0].text : headline;

      return {
        official: headline,
        genZ: genZText.trim(),
        confidence: 0.85,
        method: "ai_generated",
        replacements: [],
        emoji: "💀",
      };
    } catch (error) {
      console.error("AI translation failed:", error);
      // Fallback: just add emoji
      return {
        official: headline,
        genZ: `${headline} 💀`,
        confidence: 0.4,
        method: "rule_based",
        replacements: [],
        emoji: "💀",
      };
    }
  }

  /**
   * Cache management
   */
  private async getFromCache(headline: string): Promise<TranslationResult | null> {
    try {
      const cached = await redis.get(`headline:${headline}`);
      return cached ? JSON.parse(cached) : null;
    } catch {
      return null;
    }
  }

  private async saveToCache(headline: string, result: TranslationResult): Promise<void> {
    try {
      // Cache for 30 days
      await redis.setex(`headline:${headline}`, 2592000, JSON.stringify(result));
    } catch (error) {
      console.error("Cache write failed:", error);
    }
  }
}

// ============================================
// PART 5: EXPRESS API ENDPOINTS
// ============================================

import express from "express";

const app = express();
const translator = new HeadlineTranslator(slangDictionary);

app.use(express.json());

/**
 * POST /api/translate
 * Translate a single headline
 */
app.post("/api/translate", async (req, res) => {
  try {
    const { headline } = req.body;

    if (!headline || typeof headline !== "string") {
      return res.status(400).json({ error: "Invalid headline" });
    }

    const result = await translator.translate(headline);

    res.json(result);
  } catch (error) {
    console.error("Translation error:", error);
    res.status(500).json({ error: "Translation failed" });
  }
});

/**
 * POST /api/translate-batch
 * Translate multiple headlines at once
 */
app.post("/api/translate-batch", async (req, res) => {
  try {
    const { headlines } = req.body;

    if (!Array.isArray(headlines)) {
      return res.status(400).json({ error: "Expected array of headlines" });
    }

    const results = await Promise.all(
      headlines.map((headline) => translator.translate(headline))
    );

    res.json({ results });
  } catch (error) {
    console.error("Batch translation error:", error);
    res.status(500).json({ error: "Batch translation failed" });
  }
});

/**
 * GET /api/health
 * Health check
 */
app.get("/api/health", (req, res) => {
  res.json({ status: "ok" });
});

// ============================================
// PART 6: FLUTTER INTEGRATION HELPER
// ============================================

/**
 * Example Flutter integration class
 */

const flutterIntegrationExample = `
// Flutter: lib/services/translation_service.dart

import 'package:http/http.dart' as http;
import 'dart:convert';

class TranslationService {
  static const String baseUrl = 'https://api.yourapp.com';

  static Future<Map<String, dynamic>> translateHeadline(String headline) async {
    try {
      final response = await http.post(
        Uri.parse('\$baseUrl/api/translate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'headline': headline}),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to translate');
    } catch (e) {
      print('Translation error: \$e');
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> batchTranslate(
    List<String> headlines,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('\$baseUrl/api/translate-batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'headlines': headlines}),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['results']);
      }
      throw Exception('Batch translation failed');
    } catch (e) {
      print('Batch translation error: \$e');
      return [];
    }
  }
}

// Usage in your FactCheckCard widget:
class FactCheckCard extends StatefulWidget {
  final String officialHeadline;

  @override
  State<FactCheckCard> createState() => _FactCheckCardState();
}

class _FactCheckCardState extends State<FactCheckCard> {
  String? genZHeadline;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchTranslation();
  }

  Future<void> _fetchTranslation() async {
    setState(() => isLoading = true);
    final result = await TranslationService.translateHeadline(
      widget.officialHeadline,
    );
    setState(() {
      genZHeadline = result['genZ'];
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.officialHeadline,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        SizedBox(height: 12),
        if (isLoading)
          ShimmerLoader()
        else if (genZHeadline != null)
          Text(
            genZHeadline!,
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Colors.grey[400],
              height: 1.4,
            ),
          ),
      ],
    );
  }
}
`;

// ============================================
// START SERVER
// ============================================

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`🚀 Headline Translation Server running on port \${PORT}`);
  console.log(`📝 Endpoint: POST /api/translate`);
  console.log(`📦 Batch: POST /api/translate-batch`);
  console.log(`❤️  Health: GET /api/health`);
});

export { HeadlineTranslator, WordMatcher, ContextAnalyzer };
