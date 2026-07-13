/// FACT CHECK CARD WIDGET WITH AUTOMATIC TRANSLATION
/// Handles Gen Z headline translation with graceful fallbacks

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ============================================
// PART 1: TRANSLATION SERVICE
// ============================================

class TranslationService {
  static const String baseUrl = 'https://api.yourapp.com';
  static const Duration timeout = Duration(seconds: 5);

  /// Translate a single headline
  static Future<TranslationResult?> translateHeadline(String headline) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/translate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'headline': headline}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TranslationResult.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Translation API error: $e');
      return null;
    }
  }

  /// Batch translate multiple headlines
  static Future<List<TranslationResult>> batchTranslate(
    List<String> headlines,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/translate-batch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'headlines': headlines}),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['results'] as List)
            .map((r) => TranslationResult.fromJson(r))
            .toList();
      }
      return [];
    } catch (e) {
      print('Batch translation error: $e');
      return [];
    }
  }
}

// ============================================
// PART 2: DATA MODELS
// ============================================

class TranslationResult {
  final String official;
  final String genZ;
  final double confidence;
  final String method;
  final String emoji;

  TranslationResult({
    required this.official,
    required this.genZ,
    required this.confidence,
    required this.method,
    required this.emoji,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    return TranslationResult(
      official: json['official'] ?? '',
      genZ: json['genZ'] ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      method: json['method'] ?? 'unknown',
      emoji: json['emoji'] ?? '💀',
    );
  }

  Map<String, dynamic> toJson() => {
        'official': official,
        'genZ': genZ,
        'confidence': confidence,
        'method': method,
        'emoji': emoji,
      };
}

// ============================================
// PART 3: CLIENT-SIDE FALLBACK TRANSLATOR
// ============================================

class ClientSideFallbackTranslator {
  // Simple rule-based replacements (for when server is down)
  static const Map<String, String> replacements = {
    // Truth & lies
    'lie': 'cap',
    'lies': 'cap',
    'false': 'cap',
    'fake': 'cap',
    'hoax': 'cap',
    'suspicious': 'sus',
    'questionable': 'sus',
    'proven': 'caught in 4K',
    'confirmed': 'no cap',
    'verified': 'no cap',

    // Quality assessment
    'amazing': 'slaps',
    'awesome': 'slaps',
    'excellent': 'bussin',
    'great': 'fire',
    'succeeded': 'ate',
    'failed': 'cooked',
    'tired': 'cooked',
    'mediocre': 'mid',
    'boring': 'mid',
    'crazy': 'wild',
    'insane': 'wild',

    // Emphasis
    'really': 'fr',
    'truly': 'fr',
    'honestly': 'fr',
    'no': 'nahhh',
    'absolutely': 'lowkey',
    'somewhat': 'lowkey',
    'obviously': 'highkey',
  };

  static const Map<String, String> emojiMap = {
    'false': '🧢',
    'cap': '🧢',
    'sus': '🤨',
    'verified': '✅',
    'no cap': '✅',
    'amazing': '🔥',
    'slaps': '🔥',
    'failed': '💀',
    'cooked': '💀',
    'wild': '🤪',
    'excellent': '👌',
    'bussin': '👌',
  };

  /// Simple client-side translation (very basic)
  static String translateBasic(String headline) {
    String result = headline.toLowerCase();

    // Replace each term
    replacements.forEach((formal, slang) {
      result = result.replaceAll(RegExp(r'\b' + formal + r'\b'), slang);
    });

    // Capitalize first letter
    if (result.isNotEmpty) {
      result = result[0].toUpperCase() + result.substring(1);
    }

    return result;
  }

  /// Get emoji based on headline content
  static String getEmoji(String headline) {
    final lowerHeadline = headline.toLowerCase();

    for (var entry in emojiMap.entries) {
      if (lowerHeadline.contains(entry.key)) {
        return entry.value;
      }
    }

    return '💀'; // Default emoji
  }
}

// ============================================
// PART 4: SHIMMER LOADING EFFECT
// ============================================

class ShimmerLoader extends StatefulWidget {
  final double width;
  final double height;

  const ShimmerLoader({
    this.width = double.infinity,
    this.height = 20,
  });

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.grey[800]!,
            Colors.grey[600]!,
            Colors.grey[800]!,
          ],
          stops: [
            0,
            _controller.value,
            1,
          ],
        ),
      ),
    );
  }
}

// ============================================
// PART 5: FACT CHECK CARD WIDGET
// ============================================

class FactCheckCard extends StatefulWidget {
  final String officialHeadline;
  final String sourceId;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onSwipeUp;

  const FactCheckCard({
    required this.officialHeadline,
    required this.sourceId,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
  });

  @override
  State<FactCheckCard> createState() => _FactCheckCardState();
}

class _FactCheckCardState extends State<FactCheckCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  TranslationResult? translationResult;
  bool isLoading = false;
  bool usedFallback = false;
  Offset dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    _fetchTranslation();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Fetch translation from backend, fallback to client-side if needed
  Future<void> _fetchTranslation() async {
    setState(() => isLoading = true);

    // Try to get from backend
    final result = await TranslationService.translateHeadline(
      widget.officialHeadline,
    );

    if (result != null) {
      setState(() {
        translationResult = result;
        isLoading = false;
        usedFallback = false;
      });
    } else {
      // Fallback to client-side translation
      final fallbackTranslation =
          ClientSideFallbackTranslator.translateBasic(widget.officialHeadline);
      final emoji = ClientSideFallbackTranslator.getEmoji(
        widget.officialHeadline,
      );

      setState(() {
        translationResult = TranslationResult(
          official: widget.officialHeadline,
          genZ: fallbackTranslation,
          confidence: 0.4,
          method: 'client_side_fallback',
          emoji: emoji,
        );
        isLoading = false;
        usedFallback = true;
      });
    }
  }

  /// Handle swipe gestures
  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      dragOffset = details.globalPosition;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final magnitude = velocity.distance;

    if (magnitude < 100) {
      // Too slow, reset
      setState(() => dragOffset = Offset.zero);
      return;
    }

    // Swipe right (true)
    if (velocity.dx > 0) {
      widget.onSwipeRight?.call();
    }
    // Swipe left (false)
    else if (velocity.dx < 0) {
      widget.onSwipeLeft?.call();
    }
    // Swipe up (save)
    else if (velocity.dy < 0) {
      widget.onSwipeUp?.call();
    }

    setState(() => dragOffset = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: _handleDragUpdate,
      onPanEnd: _handleDragEnd,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.translate(
            offset: dragOffset * 0.3, // Subtle parallax
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey[900]!,
                    Colors.grey[800]!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Official headline
                  Text(
                    widget.officialHeadline,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                  ),

                  SizedBox(height: 16),

                  // Gen Z translation
                  if (isLoading)
                    ShimmerLoader(height: 24)
                  else if (translationResult != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              translationResult!.emoji,
                              style: TextStyle(fontSize: 20),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                translationResult!.genZ,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey[300],
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Show confidence indicator if low confidence or fallback used
                        if (usedFallback)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              '(AI assistant offline - quick translation)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber[600],
                              ),
                            ),
                          ),
                      ],
                    ),

                  SizedBox(height: 20),

                  // Swipe instructions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _SwipeHint(icon: '👈', label: 'Cap', color: Colors.red),
                      _SwipeHint(icon: '💾', label: 'Save', color: Colors.blue),
                      _SwipeHint(icon: '👉', label: 'True', color: Colors.green),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================
// PART 6: SWIPE HINT WIDGET
// ============================================

class _SwipeHint extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;

  const _SwipeHint({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(icon, style: TextStyle(fontSize: 20)),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
}

// ============================================
// PART 7: EXAMPLE USAGE IN MAIN APP
// ============================================

class FactCheckScreen extends StatefulWidget {
  @override
  State<FactCheckScreen> createState() => _FactCheckScreenState();
}

class _FactCheckScreenState extends State<FactCheckScreen> {
  final List<String> headlines = [
    "NTA exposed fake Telegram channels selling Re-NEET papers",
    "Supreme Court denied urgent hearing",
    "30 students caught cheating in entrance exam",
    "Government released new AI policy guidelines",
    "RBI increased interest rates by 0.5%",
  ];

  int currentIndex = 0;

  void _handleSwipeLeft() {
    // User guessed "false"
    _showResult(false, Random().nextBool());
  }

  void _handleSwipeRight() {
    // User guessed "true"
    _showResult(true, Random().nextBool());
  }

  void _handleSwipeUp() {
    // User wants to save
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved! 💾')),
    );
    _nextCard();
  }

  void _showResult(bool userGuess, bool isCorrect) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCorrect ? '✅ Correct!' : '❌ Wrong guess'),
        content: Text(
          isCorrect
              ? 'You nailed it! +10 XP'
              : 'Nah, that was wrong. Here\'s the real deal...',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _nextCard();
            },
            child: Text('Next'),
          ),
        ],
      ),
    );
  }

  void _nextCard() {
    if (currentIndex < headlines.length - 1) {
      setState(() => currentIndex++);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You completed today\'s fact checks!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('🔥 9 Day Streak | ⚡ 240 XP'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: FactCheckCard(
            officialHeadline: headlines[currentIndex],
            sourceId: 'news_${currentIndex}',
            onSwipeLeft: _handleSwipeLeft,
            onSwipeRight: _handleSwipeRight,
            onSwipeUp: _handleSwipeUp,
          ),
        ),
      ),
    );
  }
}
