import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../env.dart';
import '../models/film.dart';

/// A single CBVR result returned by Gemini.
class CbvrResult {
  final String filmId;
  final int score; // 0–100 relevance score
  final String reason; // short explanation from Gemini

  const CbvrResult({
    required this.filmId,
    required this.score,
    required this.reason,
  });
}

/// Content-Based Video Retrieval service.
///
/// Sends a natural-language query along with all film metadata to Gemini,
/// which ranks the films by semantic relevance and returns scores + reasons.
class CbvrService {
  static const String _apiKey = geminiApiKey;

  /// Ranks [films] against the given [query] using Gemini.
  ///
  /// Returns a list of [CbvrResult] objects sorted by descending score.
  /// Only films with a score >= [minScore] are included.
  static Future<List<CbvrResult>> search(
    String query,
    List<Film> films, {
    int minScore = 15,
  }) async {
    if (query.trim().isEmpty || films.isEmpty) return [];

    // Build a compact metadata payload for each film to keep the prompt concise.
    final filmMetadata = films.map((f) {
      return {
        'id': f.id,
        'title': f.title,
        'genre': f.genre,
        'year': f.year,
        'description': f.description.length > 200
            ? '${f.description.substring(0, 200)}...'
            : f.description,
        'aiSummary': f.aiSummary.length > 300
            ? '${f.aiSummary.substring(0, 300)}...'
            : f.aiSummary,
        'keywords': f.aiKeywords,
        // Core of true CBVR: Gemini Vision's analysis of actual video frames
        'visualContent': f.visualDescription.isNotEmpty
            ? f.visualDescription
            : 'No visual analysis available.',
      };
    }).toList();

    final prompt = '''
You are an expert Content-Based Video Retrieval (CBVR) system for a Philippine university documentary streaming platform called PSAUniFilms.

A user has entered the following search query:
"$query"

Below is the full list of available films. Each film has:
- Text metadata (title, genre, description, AI summary, keywords)
- "visualContent": a Gemini Vision analysis of the ACTUAL VIDEO FRAMES describing what is
  visually present (number of people, their genders, activities, setting, emotions, objects).
  This is the most important field for CBVR — use it to match visual queries.

Film data:
${jsonEncode(filmMetadata)}

Your task is to analyze the user's intent and rank ONLY the films that are relevant.

INSTRUCTIONS:
1. Be extremely generous and perform broad semantic matching. For example, if the query is "girl" or "batang ina" (young mother), you MUST include films about women, mothers, female students, or young ladies even if those exact words are missing.
2. For visual queries (e.g., "three girls bonding", "farmers in the field"), prioritize matching against the "visualContent" field over text metadata.
3. CROSS-LINGUAL MATCHING: If the query is in Tagalog/Filipino, you MUST translate its meaning and match it against the English metadata. For example, if the user searches "batang ina", you MUST find and return films about "young mothers", "teenage pregnancy", "women", or "girls" with a high score. Do NOT return an empty list if there are conceptually related films!
4. Be EXTREMELY generous with scoring. If there is even a slight thematic, conceptual, or visual link to the translated query (e.g. "babae" -> any film featuring female subjects), give it a score above 50.
5. Assign a relevance score 0–100 (100 = perfect match).
6. Write a short reason (max 12 words) explaining the match.
7. Only include films with score >= $minScore.
8. Sort from highest to lowest score.

Respond ONLY with raw JSON (no markdown):
{
  "results": [
    {"filmId": "abc123", "score": 95, "reason": "Three young women bonding and laughing together"},
    {"filmId": "xyz456", "score": 70, "reason": "Two women in a social activity outdoors"}
  ]
}

If NO films are relevant, return: {"results": []}
''';

    try {
      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: _apiKey,
      );

      final response = await model
          .generateContent([Content.text(prompt)]).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception(
            'CBVR timed out. Please check your connection and try again.'),
      );

      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw Exception('Gemini returned an empty response.');
      }

      // Extract JSON even if Gemini wraps it in markdown code fences.
      final jsonRegex = RegExp(r'\{[\s\S]*\}');
      final match = jsonRegex.firstMatch(text);
      if (match == null) throw Exception('Could not parse Gemini response.');

      final Map<String, dynamic> data = jsonDecode(match.group(0)!);
      final List<dynamic> rawResults = data['results'] ?? [];

      final results = rawResults
          .map((r) => CbvrResult(
                filmId: r['filmId'] as String,
                score: (r['score'] as num).toInt(),
                reason: r['reason'] as String,
              ))
          .where((r) => r.score >= minScore)
          .toList();

      // Sort descending by score (Gemini usually does this but ensure it).
      results.sort((a, b) => b.score.compareTo(a.score));

      return results;
    } catch (e, stack) {
      // Log the full error so it's visible in the debug console.
      debugPrint('❌ CbvrService.search error: $e');
      debugPrint('Stack: $stack');
      
      // Provide a user-friendly error for rate limits (Quota exceeded)
      if (e.toString().contains('Quota exceeded') || e.toString().contains('429')) {
        throw Exception('Smart Search is currently busy due to high traffic. Please wait a few seconds and try again.');
      }
      
      // Re-throw so the UI can show a proper error.
      rethrow;
    }
  }
}
