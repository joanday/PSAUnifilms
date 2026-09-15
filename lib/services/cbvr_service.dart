import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  /// Ranks [films] against the given [query] using Firebase Vector Search.
  ///
  /// Returns a list of [CbvrResult] objects sorted by descending score.
  static Future<List<CbvrResult>> search(
    String query,
    List<Film> films,
  ) async {
    if (query.trim().isEmpty) return [];

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('searchFilmsCBVR');
      final result = await callable.call({'query': query.trim()});
      
      final data = result.data as Map<dynamic, dynamic>;
      final rawResults = data['results'] as List<dynamic>;
      
      List<CbvrResult> cbvrResults = [];
      Set<String> seenIds = {};

      // 1. FIRST, find exact matches locally and add them with score 100!
      final q = query.trim().toLowerCase();
      for (final film in films) {
          if (film.title.toLowerCase().contains(q) ||
              film.director.toLowerCase().contains(q) ||
              film.genre.toLowerCase().contains(q) ||
              film.aiKeywords.any((k) => k.toLowerCase().contains(q)) ||
              film.cbvrKeywords.any((k) => k.toLowerCase().contains(q))) {
              
              cbvrResults.add(CbvrResult(
                  filmId: film.id,
                  score: 100, // perfect score for exact match
                  reason: "Exact keyword match found in document.",
              ));
              seenIds.add(film.id);
          }
      }
      
      // 2. THEN, add the AI vector search results
      for (int i = 0; i < rawResults.length; i++) {
        final doc = rawResults[i];
        final id = doc['id'] as String;
        
        // Ensure the film actually exists in our local list before returning it
        if (!films.any((f) => f.id == id)) continue;
        if (seenIds.contains(id)) continue;
        
        // Vector Search returns them ranked by nearest neighbor distance.
        // We will assign a descending fake score for the UI from 99 down to 80.
        int score = 99 - (i * 2); 
        
        // Try to pull a highlight from cbvrData keywords if it exists
        String reason = "Semantically matched to your search query using Vector AI.";
        if (doc['cbvrData'] != null) {
            final keywords = doc['cbvrData']['searchKeywords'] as List<dynamic>?;
            if (keywords != null && keywords.isNotEmpty) {
                reason = "Matched themes: ${keywords.take(3).join(', ')}";
            }
        }
        
        cbvrResults.add(CbvrResult(
          filmId: id,
          score: score,
          reason: reason,
        ));
        seenIds.add(id);
      }

      return cbvrResults;
    } catch (e, stack) {
      debugPrint('❌ CbvrService.search error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }
}
