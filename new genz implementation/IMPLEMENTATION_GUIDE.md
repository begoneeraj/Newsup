# Gen Z Headline Translation System - Implementation Guide

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ FactCheckCard Widget                                         │   │
│  │  • Displays official headline                                │   │
│  │  • Fetches Gen Z translation                                │   │
│  │  • Handles swipe gestures                                   │   │
│  │  • Shows loading state with shimmer                         │   │
│  └───────────────┬──────────────────────────────────────────────┘   │
│                  │                                                    │
│                  ├─────────────────────────────────┐                 │
│                  │                                 │                 │
│        ┌─────────▼────────────┐       ┌──────────▼──────────┐       │
│        │ TranslationService   │       │ ClientSideFallback  │       │
│        │ (HTTP calls)         │       │ (when offline)      │       │
│        └─────────┬────────────┘       └─────────────────────┘       │
│                  │                                                    │
└──────────────────┼────────────────────────────────────────────────────┘
                   │ HTTPS POST
                   │
         ┌─────────▼──────────────────────────────┐
         │   BACKEND TRANSLATION SERVICE          │
         │   Node.js + Express                    │
         ├──────────────────────────────────────┤
         │                                      │
         │  ┌───────────────────────────────┐   │
         │  │ /api/translate endpoint       │   │
         │  │ • Input: headline string      │   │
         │  │ • Output: TranslationResult   │   │
         │  └──────────────┬────────────────┘   │
         │                 │                    │
         │     ┌───────────┴────────────┐      │
         │     │                        │      │
         │  ┌──▼──────────┐   ┌────────▼──┐   │
         │  │ Redis Cache │   │ Claude API │   │
         │  │             │   │            │   │
         │  │ 7-day TTL   │   │ Fallback   │   │
         │  │ 85% hit     │   │ only if    │   │
         │  │ rate        │   │ no cache   │   │
         │  └─────────────┘   └────────────┘   │
         │                                      │
         │  ┌───────────────────────────────┐   │
         │  │ Word Matcher (Rule-based)     │   │
         │  │ • Pattern matching            │   │
         │  │ • Context analysis            │   │
         │  │ • Emoji selection             │   │
         │  └───────────────────────────────┘   │
         │                                      │
         └──────────────────────────────────────┘
```

---

## Step-by-Step Implementation Roadmap

### PHASE 1: Backend Setup (Week 1-2)

#### 1.1 Initialize Node.js Project

```bash
# Create project
mkdir headline-translator && cd headline-translator
npm init -y

# Install dependencies
npm install express cors dotenv redis @anthropic-ai/sdk
npm install --save-dev typescript ts-node @types/node

# Create directory structure
mkdir -p src/{services,routes,middleware,utils}
```

#### 1.2 Environment Setup

```env
# .env
PORT=3000
REDIS_HOST=localhost
REDIS_PORT=6379
ANTHROPIC_API_KEY=your_api_key_here
NODE_ENV=development
```

#### 1.3 Deploy Redis

**Option A: Local Development**
```bash
# Install Redis
brew install redis  # macOS
# or apt-get install redis-server  # Linux

# Start Redis
redis-server
```

**Option B: Cloud Redis**
```bash
# Using Redis Cloud (https://redis.com/cloud/)
# Or Render.com (free tier)

# Update .env
REDIS_HOST=your-redis-cloud-host
REDIS_PORT=your-port
REDIS_PASSWORD=your-password
```

#### 1.4 Set up Anthropic API

```bash
# Get API key from https://console.anthropic.com
# Add to .env:
ANTHROPIC_API_KEY=sk-ant-xxxxx
```

---

### PHASE 2: Backend Development (Week 2-3)

#### 2.1 Create Core Services

**File: `src/services/WordMatcher.ts`**

```typescript
import { SlangDictionary, SlangTerm } from '../types';

export class WordMatcher {
  private dictionary: SlangDictionary;

  constructor(dict: SlangDictionary) {
    this.dictionary = dict;
  }

  findMatches(text: string): Array<{
    formal: string;
    slang: string;
    emoji?: string;
  }> {
    const matches: any[] = [];
    const lowerText = text.toLowerCase();

    Object.values(this.dictionary).forEach((terms) => {
      terms.forEach((term) => {
        term.formal.forEach((formalWord) => {
          const regex = new RegExp(`\\b${formalWord}\\b`, 'gi');
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

  replaceWords(
    text: string,
    matches: Array<{ formal: string; slang: string }>
  ): string {
    let result = text;
    matches.forEach(({ formal, slang }) => {
      const regex = new RegExp(`\\b${formal}\\b`, 'gi');
      result = result.replace(regex, slang);
    });
    return result;
  }
}
```

**File: `src/services/ContextAnalyzer.ts`**

```typescript
export class ContextAnalyzer {
  analyzeContext(headline: string) {
    const text = headline.toLowerCase();
    
    // Detect tone
    const tones = {
      funny: ['banned', 'exposed', 'caught', 'failed'],
      serious: ['government', 'court', 'policy'],
      shocking: ['death', 'attack', 'explosion'],
      sad: ['died', 'loss', 'tragedy'],
      inspiring: ['saved', 'helped', 'awarded'],
    };

    let tone = 'serious';
    for (const [key, keywords] of Object.entries(tones)) {
      if (keywords.some((kw) => text.includes(kw))) {
        tone = key;
        break;
      }
    }

    // Check if suitable for sarcasm
    const unsuitable = ['death', 'suicide', 'murder', 'rape', 'abuse'];
    const canBeSarcastic = !unsuitable.some((kw) => text.includes(kw));

    return { tone, canBeSarcastic };
  }
}
```

**File: `src/services/HeadlineTranslator.ts`**

```typescript
import { Anthropic } from '@anthropic-ai/sdk';
import { Redis } from 'redis';

export class HeadlineTranslator {
  constructor(
    private redis: Redis,
    private anthropic: Anthropic,
    private matcher: WordMatcher,
    private analyzer: ContextAnalyzer
  ) {}

  async translate(headline: string) {
    // 1. Check cache
    const cached = await this.getFromCache(headline);
    if (cached) return cached;

    // 2. Try rule-based matching
    const matches = this.matcher.findMatches(headline);
    if (matches.length > 0) {
      const context = this.analyzer.analyzeContext(headline);
      if (context.canBeSarcastic) {
        const translated = this.matcher.replaceWords(headline, matches);
        const result = {
          official: headline,
          genZ: translated,
          confidence: 0.75,
          method: 'rule_based',
          emoji: matches[0]?.emoji || '💀',
        };
        await this.saveToCache(headline, result);
        return result;
      }
    }

    // 3. Fallback to AI
    return this.generateWithAI(headline);
  }

  private async generateWithAI(headline: string) {
    const context = this.analyzer.analyzeContext(headline);
    
    const response = await this.anthropic.messages.create({
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 50,
      system: `You are a Gen Z translator. Convert headlines to Gen Z speak (max 15 words).
      
Use only: cap, sus, no cap, fr, bro, slay, bussin, cooked, mid, wild, nahhh, lowkey, 💀 😭 🔥
Keep it funny, not offensive.`,
      messages: [
        {
          role: 'user',
          content: `Translate: "${headline}"`,
        },
      ],
    });

    const genZText =
      response.content[0].type === 'text' ? response.content[0].text : headline;

    const result = {
      official: headline,
      genZ: genZText.trim(),
      confidence: 0.85,
      method: 'ai_generated',
      emoji: '💀',
    };

    await this.saveToCache(headline, result);
    return result;
  }

  private async getFromCache(headline: string) {
    try {
      const cached = await this.redis.get(`headline:${headline}`);
      return cached ? JSON.parse(cached) : null;
    } catch {
      return null;
    }
  }

  private async saveToCache(headline: string, result: any) {
    try {
      await this.redis.setEx(
        `headline:${headline}`,
        2592000, // 30 days
        JSON.stringify(result)
      );
    } catch (error) {
      console.error('Cache write failed:', error);
    }
  }
}
```

#### 2.2 Create Express Routes

**File: `src/routes/translate.ts`**

```typescript
import { Router, Request, Response } from 'express';
import { HeadlineTranslator } from '../services/HeadlineTranslator';

export function createTranslateRouter(translator: HeadlineTranslator) {
  const router = Router();

  // Single headline
  router.post('/api/translate', async (req: Request, res: Response) => {
    try {
      const { headline } = req.body;

      if (!headline || typeof headline !== 'string') {
        return res.status(400).json({ error: 'Invalid headline' });
      }

      const result = await translator.translate(headline);
      res.json(result);
    } catch (error) {
      console.error('Translation error:', error);
      res.status(500).json({ error: 'Translation failed' });
    }
  });

  // Batch
  router.post('/api/translate-batch', async (req: Request, res: Response) => {
    try {
      const { headlines } = req.body;

      if (!Array.isArray(headlines)) {
        return res.status(400).json({ error: 'Expected array' });
      }

      const results = await Promise.all(
        headlines.map((h) => translator.translate(h))
      );

      res.json({ results });
    } catch (error) {
      console.error('Batch error:', error);
      res.status(500).json({ error: 'Batch translation failed' });
    }
  });

  return router;
}
```

#### 2.3 Create Main App File

**File: `src/index.ts`**

```typescript
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { createClient } from 'redis';
import Anthropic from '@anthropic-ai/sdk';
import { HeadlineTranslator } from './services/HeadlineTranslator';
import { WordMatcher } from './services/WordMatcher';
import { ContextAnalyzer } from './services/ContextAnalyzer';
import { createTranslateRouter } from './routes/translate';
import slangDictionary from './data/slang-dictionary.json';

dotenv.config();

const app = express();
const redis = createClient({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD,
});

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// Middleware
app.use(express.json());
app.use(cors());

// Initialize services
const matcher = new WordMatcher(slangDictionary);
const analyzer = new ContextAnalyzer();
const translator = new HeadlineTranslator(redis, anthropic, matcher, analyzer);

// Routes
app.use(createTranslateRouter(translator));

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date() });
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Translation server running on ${PORT}`);
  console.log(`📝 Endpoints:`);
  console.log(`   POST /api/translate`);
  console.log(`   POST /api/translate-batch`);
  console.log(`   GET /api/health`);
});
```

---

### PHASE 3: Flutter Integration (Week 3-4)

#### 3.1 Add HTTP Package

```bash
flutter pub add http
```

#### 3.2 Create Translation Service

Copy `translation_service.dart` into your Flutter project:

```bash
lib/
├── services/
│   └── translation_service.dart
├── widgets/
│   └── fact_check_card.dart
└── screens/
    └── fact_check_screen.dart
```

#### 3.3 Update App Configuration

**In `pubspec.yaml`:**

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.0.0
```

#### 3.4 Test Integration

```dart
// lib/main.dart
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FactCheckScreen(),
      theme: ThemeData.dark(),
    );
  }
}
```

---

### PHASE 4: Testing & Deployment (Week 4-5)

#### 4.1 Unit Tests

**File: `tests/translator.test.ts`**

```typescript
import { HeadlineTranslator } from '../src/services/HeadlineTranslator';

describe('HeadlineTranslator', () => {
  it('should cache translations', async () => {
    const headline = 'Test headline';
    const result1 = await translator.translate(headline);
    const result2 = await translator.translate(headline);
    expect(result1).toEqual(result2);
  });

  it('should use rule-based matching', async () => {
    const headline = 'False information exposed';
    const result = await translator.translate(headline);
    expect(result.method).toBe('rule_based');
  });

  it('should not translate sensitive content', async () => {
    const headline = 'Person died in tragic accident';
    const result = await translator.translate(headline);
    expect(result.confidence).toBeLessThan(0.8);
  });
});
```

#### 4.2 Deploy Backend

**Option A: Render.com (Recommended)**

```bash
# 1. Create account at render.com
# 2. Connect GitHub repo
# 3. Create new Web Service
# 4. Set environment variables
# 5. Deploy (takes 2 minutes)
```

**Option B: Railway.app**

```bash
# Install railway CLI
npm install -g @railway/cli

# Login
railway login

# Deploy
railway up
```

**Option C: Heroku (Free tier deprecated, use paid)**

```bash
# Install Heroku CLI
brew install heroku

# Login
heroku login

# Create app
heroku create your-app-name

# Deploy
git push heroku main
```

#### 4.3 Update Flutter API URL

```dart
// lib/constants.dart
const String API_BASE_URL = 'https://your-deployed-backend.com';

// In TranslationService:
static Future<TranslationResult?> translateHeadline(String headline) async {
  try {
    final response = await http.post(
      Uri.parse('$API_BASE_URL/api/translate'),
      // ...
    );
  }
}
```

#### 4.4 Performance Testing

```bash
# Test API response time
curl -X POST https://your-api.com/api/translate \
  -H "Content-Type: application/json" \
  -d '{"headline":"Test headline"}'

# Expected: < 500ms (cache hit), < 2s (AI generation)
```

---

## Monitoring & Optimization

### Cache Hit Rate Monitoring

```typescript
// Track cache performance
const cacheStats = {
  hits: 0,
  misses: 0,
  get hitRate() {
    return this.hits / (this.hits + this.misses);
  },
};

app.use((req, res, next) => {
  res.on('finish', () => {
    if (res.getHeader('X-Cache') === 'HIT') {
      cacheStats.hits++;
    } else {
      cacheStats.misses++;
    }
  });
  next();
});
```

### Cost Optimization

| Component | Cost (Monthly) |
|-----------|---|
| Claude API (10K calls) | ~$3 |
| Redis Cloud (free tier) | $0 |
| Render/Railway backend | $7-12 |
| **Total** | **~$10-15** |

**Cost Reduction Strategies:**
- Cache aggressively (85% hit rate = 85% fewer API calls)
- Batch translate headlines (less network overhead)
- Use rule-based matching for common terms

---

## Fallback & Error Handling

### Network Error Scenarios

```dart
// Scenario 1: Backend is down
// → Use ClientSideFallbackTranslator
// → Show "Quick translation" indicator

// Scenario 2: API rate limit hit
// → Queue requests
// → Use cached results
// → Show older translations

// Scenario 3: No internet
// → Load from local cache
// → Disable sync features
// → Show offline indicator
```

---

## Scaling Considerations

### When to Scale

| Metric | Action |
|--------|--------|
| >10K requests/day | Upgrade Redis tier |
| >1M headlines | Add database + full-text search |
| >50K concurrent users | Implement request queueing |

### Database Migration (Future)

```sql
-- Store translations for analytics
CREATE TABLE headline_translations (
  id UUID PRIMARY KEY,
  original_headline TEXT,
  gen_z_translation TEXT,
  confidence FLOAT,
  method VARCHAR(50),
  created_at TIMESTAMP,
  cache_hits INT DEFAULT 0
);

-- Query most-translated headlines
SELECT original_headline, COUNT(*) as count
FROM headline_translations
GROUP BY original_headline
ORDER BY count DESC;
```

---

## Testing Checklist

- [ ] Backend API returns correct format
- [ ] Cache works correctly (Redis)
- [ ] Fallback mechanism works
- [ ] Flutter app handles network errors
- [ ] Shimmer loader displays correctly
- [ ] Swipe gestures detected
- [ ] Offline mode works
- [ ] Performance <500ms average
- [ ] No crashes on edge cases
- [ ] Sensitive content not sarcastic

---

## Summary Timeline

| Week | Deliverable |
|------|---|
| 1-2 | Backend setup + services |
| 2-3 | API endpoints + testing |
| 3-4 | Flutter integration |
| 4-5 | Deployment + optimization |
| 5-6 | Monitoring + scaling |

---

## Next Steps

1. ✅ Set up Node.js backend
2. ✅ Deploy to Render/Railway
3. ✅ Integrate with Flutter
4. ✅ Test thoroughly
5. ✅ Monitor & optimize

---

## Support & Resources

- **Claude API Docs**: https://docs.anthropic.com
- **Redis Documentation**: https://redis.io/documentation
- **Flutter HTTP**: https://pub.dev/packages/http
- **Render.com Guide**: https://render.com/docs
