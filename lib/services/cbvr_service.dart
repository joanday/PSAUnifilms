import 'dart:convert';
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
    int minScore = 30,
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
      };
    }).toList();

    final prompt = '''
You are an expert Content-Based Video Retrieval (CBVR) system for a Philippine university documentary streaming platform called PSAUniFilms.

A user has entered the following search query:
"$query"

Below is the full list of available films with their metadata (title, genre, description, AI summary, and keywords):

${jsonEncode(filmMetadata)}

Your task is to analyze the user's intent and rank ONLY the films that are relevant to their query.

INSTRUCTIONS:
1. Understand the semantic meaning of the query, not just keyword overlap.
2. For each relevant film, assign a relevance score from 0 to 100 (100 = perfect match).
3. Write a short reason (max 12 words) explaining why the film matches the query.
4. Only include films with a score of $minScore or above.
5. Return films sorted from highest to lowest score.
6. The reason should be in English and describe the content match (e.g., "Shows traditional rice farming in rural Pampanga").

Respond ONLY with raw JSON in this exact format (no markdown, no extra text):
{
  "results": [
    {"filmId": "abc123", "score": 92, "reason": "Directly covers rice farming and agricultural traditions"},
    {"filmId": "xyz456", "score": 74, "reason": "Features community farming and rural Philippine life"}
  ]
}

If NO films are relevant (all scores below $minScore), return: {"results": []}
''';

    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
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
    } catch (e) {
      // Re-throw so the UI can show a proper error.
      rethrow;
    }
  }
}
