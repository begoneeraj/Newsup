# Gen Z Headline Translation - Quick Reference

## Architecture Decision Tree

```
User sees headline
    ↓
Does translation exist?
    ├─ YES → Return from cache (50ms) ✅
    └─ NO ↓
         Rule-based match available?
         ├─ YES → Replace words (100ms) ✅
         └─ NO ↓
              Internet available?
              ├─ YES → Call Claude API (1-2s) ✅
              └─ NO → Client-side fallback (50ms) ✅
```

---

## What You Need (Backend)

### Option 1: Easiest (Recommended for MVP)

```
Backend URL
    ↓
┌───────────────────────────────┐
│ POST /api/translate           │
│                               │
│ Input: {headline: "..."}      │
│ Output: {                     │
│   official: "...",            │
│   genZ: "...",                │
│   emoji: "🧢",                │
│   confidence: 0.85            │
│ }                             │
└───────────────────────────────┘
```

### Option 2: Most Efficient (Production)

```
Backend + Redis
    ↓
1. Check Redis cache
2. If miss → Call Claude API
3. Store result (7 days TTL)
4. Return result
```

### Option 3: Complete

```
Backend + Redis + Database
    ↓
1. Check Redis cache
2. If miss → Check database
3. If not in DB → Call Claude API
4. Store in both Redis + Database
5. Track analytics
```

---

## What Happens in Each Component

### Backend (Node.js)

```
Receives headline
    ↓
Check cache? (Redis) → ~85% hit rate
    ├─ HIT → Return instantly ⚡
    └─ MISS ↓
          Try word matching?
          ├─ SUCCESS (75%+) → Return ✅
          └─ FAIL ↓
               Call Claude API → Generate (1-2s)
               ↓
               Cache result (7 days)
               ↓
               Return
```

### Flutter App

```
User opens headline
    ↓
Show official headline
    ↓
Fetch from backend
    ├─ Success? → Show Gen Z version ✅
    └─ Timeout (5s)? → Use client-side fallback ✅
    
Offline? → Already cached locally ✅
```

---

## Complete Slang Dictionary

### Truth & Lies
| Formal | Gen Z |
|--------|-------|
| lie, false, fake | **cap** 🧢 |
| honest, truly, for real | **no cap** ✅ |
| suspicious, questionable | **sus** 🤨 |
| proven, caught | **caught in 4K** 📷 |

### Quality
| Formal | Gen Z |
|--------|-------|
| amazing, great | **slaps** 🔥 |
| excellent | **bussin** 👌 |
| did perfectly | **ate** 🍽️ |
| tired, exhausted | **cooked** 🍳 |
| mediocre | **mid** 😐 |
| crazy, wild | **wild** 🤪 |
| failure | **major L** ❌ |
| success | **W move** ✅ |

### People
| Formal | Gen Z |
|--------|-------|
| friend, guy | **bro** 🤖 |
| close friend | **twin** 👯‍♂️ |
| attractive person | **fynshit** ✨ |
| NPC, boring | **NPC** 🤖 |

### Emphasis
| Formal | Gen Z |
|--------|-------|
| really, truly | **fr** 💯 |
| no, nope | **nahhh** 🙅 |
| somewhat | **lowkey** 🤐 |
| obviously | **highkey** 📢 |
| meme reference | **skibidi** 🚽 |

---

## Implementation Checklist

### Week 1
- [ ] Create Node.js project
- [ ] Set up Redis (local or cloud)
- [ ] Get Anthropic API key
- [ ] Create WordMatcher service
- [ ] Create HeadlineTranslator service

### Week 2
- [ ] Create Express routes
- [ ] Test API endpoints locally
- [ ] Implement caching
- [ ] Add error handling
- [ ] Deploy to Render/Railway

### Week 3
- [ ] Update Flutter with TranslationService
- [ ] Test on real device
- [ ] Implement fallback
- [ ] Add shimmer loader
- [ ] Handle network errors

### Week 4
- [ ] Performance testing
- [ ] Cache hit rate optimization
- [ ] Cost analysis
- [ ] Monitor in production
- [ ] Collect analytics

---

## Code Snippets You'll Need

### Setup Backend
```bash
npm init -y
npm install express cors dotenv redis @anthropic-ai/sdk
npm install --save-dev typescript ts-node @types/node
```

### Setup Flutter
```bash
flutter pub add http
```

### API Call (Flutter)
```dart
final response = await http.post(
  Uri.parse('https://your-api.com/api/translate'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'headline': 'Your headline here'}),
);
```

### API Call (Backend)
```typescript
const response = await anthropic.messages.create({
  model: 'claude-3-5-sonnet-20241022',
  max_tokens: 50,
  messages: [{role: 'user', content: prompt}],
});
```

---

## Costs Breakdown

| Item | Cost |
|------|------|
| Claude API (1M tokens) | ~$3 |
| Redis Cloud (free tier) | $0 |
| Render/Railway backend | $7-12 |
| Total per month | **~$10-15** |

**Cost reduction:** Each cached result saves $0.0001. With 85% cache hit rate, you save 85% on API costs.

---

## Performance Targets

| Metric | Target | How to Achieve |
|--------|--------|---|
| Cache hit response | <100ms | Redis |
| Rule-based matching | <200ms | Optimized regex |
| AI generation | 1-2s | Claude API |
| Network timeout | 5s | Fallback ready |
| Offline mode | Works | Local cache |

---

## What NOT to Do

❌ Don't hardcode translations  
❌ Don't forget to cache  
❌ Don't skip error handling  
❌ Don't use without fallback  
❌ Don't translate sensitive content (death, abuse, etc)  
❌ Don't make API calls for every character typed  
❌ Don't forget to batch requests  

---

## Monitoring

### Check Cache Hit Rate
```typescript
const hitRate = hits / (hits + misses);
// Target: >80%
```

### Check API Performance
```bash
time curl -X POST https://your-api.com/api/translate \
  -d '{"headline":"test"}'
# Should be <200ms if cached, <2s if API call
```

### Check Error Rate
```typescript
// Track failed translations
const errorRate = errors / totalRequests;
// Should be <1%
```

---

## Deployment Checklist

### Before Going Live
- [ ] All tests passing
- [ ] Error handling works
- [ ] Cache working
- [ ] Fallback tested
- [ ] Rate limiting configured
- [ ] API key secured
- [ ] Database backups enabled
- [ ] Monitoring set up
- [ ] Load testing done
- [ ] Documentation complete

### After Going Live
- [ ] Monitor error rates
- [ ] Check cache hit rate (should be >80%)
- [ ] Monitor API costs
- [ ] Collect user feedback
- [ ] Track cache hits/misses
- [ ] Monitor response times
- [ ] Plan scaling if needed

---

## Emergency Procedures

### API Quota Exceeded
```
Use cached results only
→ Set CACHE_ONLY=true
→ Return cached translations
→ Don't call Claude API
```

### Redis Down
```
API can still work
→ Skip cache
→ Call Claude API directly
→ Slower but still functional
```

### Backend Down
```
Use client-side fallback
→ TranslationService returns null
→ ClientSideFallbackTranslator activates
→ Show "Quick translation" badge
```

---

## Testing Examples

### Test 1: Happy Path
```
Input: "Government released new AI policy"
Backend: Calls Claude API
Output: "AI just got new house rules no cap 🔥"
Cache: Stores result
Next time: Returns from cache (85% faster)
```

### Test 2: Rule-Based Match
```
Input: "False information exposed"
Backend: Matches "false" → "cap"
Output: "Cap information exposed 🧢"
No API call needed
Instant result
```

### Test 3: Fallback
```
Backend: Down/timeout
Flutter: Timeout after 5s
Fallback: ClientSideFallbackTranslator
Output: "False information exposed cap"
Shows: "(Quick translation)"
```

### Test 4: Offline
```
User: Opens app offline
Flutter: Loads cached headline
Translation: Already in device cache
Shows: Previous translation immediately
Syncs: When online again
```

---

## Real-World Examples

### Example 1: NTA News
```
Official: "NTA exposed fake Telegram channels selling Re-NEET papers"
GenZ: "Bro really thought selling fake papers was gonna work 💀"
Method: Rule-based + AI enhancement
Confidence: 0.85
```

### Example 2: Court News
```
Official: "Supreme Court denied urgent hearing"
GenZ: "Bro really said 'Not today.' 🙅"
Method: AI-generated
Confidence: 0.82
```

### Example 3: Exam News
```
Official: "30 students caught cheating in entrance exam"
GenZ: "Caught in 4K fr fr 📷"
Method: Rule-based
Confidence: 0.90
```

---

## Getting Started (30-Minute Quick Start)

### 1. Clone Template (5 min)
```bash
git clone your-repo
cd headline-translator
npm install
```

### 2. Set Up Environment (5 min)
```bash
# Add .env
PORT=3000
ANTHROPIC_API_KEY=your-key
REDIS_HOST=localhost
```

### 3. Start Services (5 min)
```bash
# Terminal 1: Redis
redis-server

# Terminal 2: Node backend
npm run dev
# Runs on http://localhost:3000
```

### 4. Test API (5 min)
```bash
curl -X POST http://localhost:3000/api/translate \
  -H "Content-Type: application/json" \
  -d '{"headline":"This is fake news"}'
```

### 5. Deploy (5 min)
```bash
# Push to GitHub
git push

# Go to Render.com → Create Web Service
# Connect repo → Deploy ✅
```

---

## Resources

- **Anthropic Docs**: https://docs.anthropic.com
- **Redis Docs**: https://redis.io/documentation
- **Render Deploy**: https://render.com/docs
- **Flutter HTTP**: https://pub.dev/packages/http

---

## Questions?

### "How much will this cost?"
A: ~$10-15/month. Cache hits save 85% of API costs.

### "What if the backend is down?"
A: App automatically uses client-side fallback. Works offline.

### "Will translations be appropriate?"
A: Yes. System checks for sensitive content (death, abuse) and won't sarcasm-ify. You review outputs.

### "Can I use different slang?"
A: Yes! Edit `genz_slang_dictionary.json` and rebuild.

### "How do I scale to millions of users?"
A: Add database + better caching. Costs ~$50-100/month at scale.

---

**Last Updated:** January 2026  
**Status:** Production Ready  
**Maintenance:** Low (30 min/week monitoring)
