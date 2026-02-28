import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../constants/app_constants.dart';

// ── Data models ────────────────────────────────────────────

class AiPricingResult {
  final String id;
  final double estimatedMarketPrice;
  final double recommendedPrice;
  final String aiAdvice;

  const AiPricingResult({
    required this.id,
    required this.estimatedMarketPrice,
    required this.recommendedPrice,
    required this.aiAdvice,
  });

  Map<String, dynamic> toFirestoreMap() => {
    'recPrice': recommendedPrice,
    'estimatedMarketPrice': estimatedMarketPrice,
    'aiAdvice': aiAdvice,
    'isAiReady': true,
  };
}

class AiDailyBriefing {
  final String headline;
  final String summary;
  final String actionLabel;
  final String actionDetail;

  const AiDailyBriefing({
    required this.headline,
    required this.summary,
    required this.actionLabel,
    required this.actionDetail,
  });
}

class AiCompetitorAlert {
  final String title;
  final String advice;
  final String urgency; // 'high' | 'medium' | 'low'

  const AiCompetitorAlert({
    required this.title,
    required this.advice,
    required this.urgency,
  });
}

class AiDemandExplanation {
  final String peakDay;
  final String explanation;
  final String pricingTip;

  const AiDemandExplanation({
    required this.peakDay,
    required this.explanation,
    required this.pricingTip,
  });
}

// ── Service ────────────────────────────────────────────────

class GeminiService {
  static final GenerativeModel _model = GenerativeModel(
    model: 'gemini-2.0-flash',
    apiKey: AppConstants.geminiApiKey,
  );

  // ── 30-minute cache — prevents hammering free tier quota ──

  static AiDailyBriefing? _cachedBriefing;
  static AiCompetitorAlert? _cachedAlert;
  static AiDemandExplanation? _cachedDemand;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 30);

  static bool get _cacheValid =>
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheDuration;

  /// Call this on manual pull-to-refresh to force fresh AI responses.
  static void clearCache() {
    _cachedBriefing = null;
    _cachedAlert = null;
    _cachedDemand = null;
    _cacheTime = null;
  }

  // ── Helper: strip Firestore Timestamps & non-encodable types ──

  static List<Map<String, dynamic>> _sanitizeProducts(
    List<Map<String, dynamic>> products,
  ) {
    return products
        .map(
          (p) => {
            'name': p['name'] ?? '',
            'price': p['price'] ?? 0,
            'unitsSold': p['unitsSold'] ?? p['sold'] ?? 0,
            'stock': p['stock'] ?? 0,
          },
        )
        .toList();
  }

  // ── Daily Briefing ─────────────────────────────────────────

  static Future<AiDailyBriefing> generateDailyBriefing({
    required String businessName,
    required String industry,
    required String region,
    required List<Map<String, dynamic>> topProducts,
  }) async {
    if (_cacheValid && _cachedBriefing != null) {
      debugPrint('GeminiService: cached briefing');
      return _cachedBriefing!;
    }

    final dayName = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][DateTime.now().weekday - 1];

    final prompt =
        '''You are a smart pricing advisor for Malaysian MSMEs.
Business context:
- Name: $businessName
- Industry: $industry
- Region: $region
- Today: $dayName
- Top products: ${jsonEncode(_sanitizeProducts(topProducts))}

Generate a short daily briefing. Output ONLY valid JSON, no markdown:
{
  "headline": "One punchy sentence summarizing today's key insight (max 10 words)",
  "summary": "2-3 sentences of actionable advice based on their industry, region, and day of week",
  "action_label": "Short action label (3-5 words)",
  "action_detail": "One specific thing they should do today"
}''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text =
          response.text
              ?.replaceAll('```json', '')
              .replaceAll('```', '')
              .trim() ??
          '{}';
      final result = jsonDecode(text) as Map<String, dynamic>;
      final briefing = AiDailyBriefing(
        headline: result['headline'] ?? 'Good morning!',
        summary: result['summary'] ?? 'Check your pricing today.',
        actionLabel: result['action_label'] ?? 'Take action',
        actionDetail: result['action_detail'] ?? '',
      );
      _cachedBriefing = briefing;
      _cacheTime ??= DateTime.now();
      return briefing;
    } catch (e) {
      debugPrint('GeminiService dailyBriefing error: $e');
      return const AiDailyBriefing(
        headline: 'Ready to optimize today?',
        summary:
            'Review your top products and adjust pricing based on current demand.',
        actionLabel: 'Run simulation',
        actionDetail: 'Open the simulator to test a price change.',
      );
    }
  }

  // ── Competitor Alert ───────────────────────────────────────

  static Future<AiCompetitorAlert> generateCompetitorAlert({
    required String industry,
    required String region,
    required List<Map<String, dynamic>> products,
  }) async {
    if (_cacheValid && _cachedAlert != null) {
      debugPrint('GeminiService: cached alert');
      return _cachedAlert!;
    }

    final hasProducts = products.isNotEmpty;
    final clean = _sanitizeProducts(products);

    final productContext = hasProducts
        ? '''Seller's actual products:\n${clean.take(3).map((p) => '- ${p['name']} at RM${p['price']}, ${p['unitsSold']} units sold').join('\n')}'''
        : 'No specific products yet — give general industry advice.';

    final prompt =
        '''You are a sharp competitive pricing analyst for Malaysian MSMEs on Shopee/TikTok.

Context:
- Industry: $industry
- Region: $region
- $productContext

${hasProducts ? "Simulate a REALISTIC competitor scenario targeting one of the seller's actual products. Mention the product name and prices." : 'Simulate a realistic general competitor scenario for this industry and region.'}

Output ONLY valid JSON, no markdown:
{
  "title": "Specific alert title (max 12 words)",
  "advice": "2-3 sentences of sharp, actionable advice for TODAY",
  "urgency": "medium"
}
urgency must be exactly one of: "high", "medium", "low"''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text =
          response.text
              ?.replaceAll('```json', '')
              .replaceAll('```', '')
              .trim() ??
          '{}';
      final result = jsonDecode(text) as Map<String, dynamic>;
      final alert = AiCompetitorAlert(
        title: result['title'] ?? 'Competitor activity detected',
        advice: result['advice'] ?? 'Monitor the market closely.',
        urgency: result['urgency'] ?? 'medium',
      );
      _cachedAlert = alert;
      _cacheTime ??= DateTime.now();
      return alert;
    } catch (e) {
      debugPrint('GeminiService competitorAlert error: $e');
      return const AiCompetitorAlert(
        title: 'Competitor dropped price by RM2',
        advice:
            'DO NOT lower your price. Demand remains inelastic — maintaining current price preserves your margin.',
        urgency: 'medium',
      );
    }
  }

  // ── Demand Forecast Explanation ────────────────────────────

  static Future<AiDemandExplanation> explainDemandForecast({
    required String industry,
    required String region,
    required Map<String, double> weeklyDemand,
  }) async {
    if (_cacheValid && _cachedDemand != null) {
      debugPrint('GeminiService: cached demand explanation');
      return _cachedDemand!;
    }

    final peakEntry = weeklyDemand.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );

    final prompt =
        '''You are a demand forecasting expert for Malaysian MSMEs.
Context:
- Industry: $industry
- Region: $region
- Weekly demand pattern (0-1 scale): ${jsonEncode(weeklyDemand)}
- Peak day: ${peakEntry.key}

Output ONLY valid JSON, no markdown:
{
  "peak_day": "${peakEntry.key}",
  "explanation": "1-2 sentences explaining WHY this day is peak for this industry/region",
  "pricing_tip": "1 specific pricing action to take on peak day"
}''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text =
          response.text
              ?.replaceAll('```json', '')
              .replaceAll('```', '')
              .trim() ??
          '{}';
      final result = jsonDecode(text) as Map<String, dynamic>;
      final explanation = AiDemandExplanation(
        peakDay: result['peak_day'] ?? peakEntry.key,
        explanation: result['explanation'] ?? '',
        pricingTip: result['pricing_tip'] ?? '',
      );
      _cachedDemand = explanation;
      _cacheTime ??= DateTime.now();
      return explanation;
    } catch (e) {
      debugPrint('GeminiService demandExplanation error: $e');
      return AiDemandExplanation(
        peakDay: peakEntry.key,
        explanation:
            'Friday sees highest demand driven by end-of-week shopping patterns in Malaysia.',
        pricingTip:
            'Consider a 5-8% price increase on Fridays to capture peak demand.',
      );
    }
  }

  // ── Single Product Analysis ────────────────────────────────

  static Future<AiPricingResult> analyseSingleProduct({
    required String id,
    required String name,
    required double price,
    required int stock,
    required int unitsSold,
  }) async {
    final prompt =
        '''You are an expert e-commerce pricing algorithm for Malaysia.
Analyze this product:
${jsonEncode({"id": id, "name": name, "price": price, "stock": stock, "sold": unitsSold})}

Output ONLY valid JSON, no markdown:
{
  "estimated_market_price": 100.00,
  "recommended_price": 95.00,
  "ai_advice": "Short 1-sentence advice in English"
}''';

    final response = await _model.generateContent([Content.text(prompt)]);
    final text =
        response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ??
        '{}';
    final result = jsonDecode(text) as Map<String, dynamic>;

    return AiPricingResult(
      id: id,
      estimatedMarketPrice: (result['estimated_market_price'] as num)
          .toDouble(),
      recommendedPrice: (result['recommended_price'] as num).toDouble(),
      aiAdvice: result['ai_advice'].toString(),
    );
  }

  // ── Batch Analysis ─────────────────────────────────────────

  static Future<List<AiPricingResult>> analyseBatch(
    List<Map<String, dynamic>> products,
  ) async {
    final batchJson = products
        .map(
          (p) => {
            "id": p['id'],
            "name": p['name'],
            "price": p['price'],
            "stock": p['stock'],
            "sold": p['sold'],
          },
        )
        .toList();

    final prompt =
        '''You are an expert e-commerce pricing algorithm for Malaysia.
Analyze these products:
${jsonEncode(batchJson)}

Output ONLY a valid JSON array, no markdown:
[
  {
    "id": "item_id_here",
    "estimated_market_price": 100.00,
    "recommended_price": 95.00,
    "ai_advice": "Short 1-sentence advice in English"
  }
]''';

    final response = await _model.generateContent([Content.text(prompt)]);
    final text =
        response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ??
        '[]';

    final List<dynamic> raw = jsonDecode(text);
    final results = <AiPricingResult>[];

    for (final item in raw) {
      try {
        results.add(
          AiPricingResult(
            id: item['id'].toString(),
            estimatedMarketPrice: (item['estimated_market_price'] as num)
                .toDouble(),
            recommendedPrice: (item['recommended_price'] as num).toDouble(),
            aiAdvice: item['ai_advice'].toString(),
          ),
        );
      } catch (e) {
        debugPrint('GeminiService: failed to parse item $item — $e');
      }
    }
    return results;
  }
}
