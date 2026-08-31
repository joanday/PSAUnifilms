import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../env.dart';

class AiMetadata {
  final String summary;
  final List<String> keywords;

  AiMetadata({required this.summary, required this.keywords});
}

class AiService {
  // Loaded from env.dart to protect secrets from GitHub
  static const String _apiKey = geminiApiKey;

  static Future<AiMetadata> generateMetadata(String title, String description) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: _apiKey,
      );

      final prompt = '''
You are an expert AI video analysis tool for a university documentary platform in the Philippines.
Your task is to provide an accurate summary and keywords for a documentary.

The user provided the following details:
Title: "$title"
Description: "$description"

IMPORTANT INSTRUCTIONS:
1. Generate a highly professional, accurate summary (3-4 sentences max) in ENGLISH describing the true themes, cultural relevance, and potential impact of this documentary based on its title and description.
2. Generate a list of 5 to 8 highly relevant searchable keywords/tags (these can be English, Tagalog, or Kapampangan) that describe the actual concepts discussed.

Format your response exactly as JSON like this (no markdown tags, just the raw JSON):
{
  "summary": "Your accurate professional summary here...",
  "keywords": ["keyword1", "keyword2", "keyword3"]
}
''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('AI generation timed out after 15 seconds. Please check your internet connection or try again.'),
      );
      
      final text = response.text;
      if (text != null) {
        // Use RegEx to extract the JSON block if it's wrapped in markdown or conversational text
        final jsonRegEx = RegExp(r'\{[\s\S]*\}');
        final match = jsonRegEx.firstMatch(text);
        
        if (match != null) {
          final cleanText = match.group(0)!;
          final Map<String, dynamic> data = jsonDecode(cleanText);
          
          return AiMetadata(
            summary: data['summary'] ?? '',
            keywords: List<String>.from(data['keywords'] ?? []),
          );
        } else {
          throw Exception('Failed to extract JSON from AI response.');
        }
      }
    } catch (e) {
      debugPrint('API Error: $e');
      return AiMetadata(
        summary: 'API ERROR: $e',
        keywords: ['Error'],
      );
    }
    throw Exception('AI returned an empty response.');
  }

  /// True CBVR: analyzes actual video frames using Gemini Vision.
  static Future<String> generateVisualDescription(String thumbnailUrl) async {
    if (thumbnailUrl.isEmpty) return 'Visual analysis unavailable: no thumbnail provided.';
    
    try {
      final response = await http.get(Uri.parse(thumbnailUrl));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return 'Visual analysis unavailable: could not fetch thumbnail.';
      }

      final imagePart = DataPart('image/jpeg', response.bodyBytes);

      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: _apiKey,
      );

      const textPrompt = '''
You are a visual content analyzer for a Philippine university documentary platform.
You are given a frame capture from a documentary video.

Analyze the frame carefully and provide a comprehensive visual description.
Your description MUST cover ALL of the following aspects that are visible:

1. PEOPLE: How many people appear? Describe their apparent gender, age group, and number.
   (e.g., "three young women", "two elderly men", "a group of about 10 children")
2. ACTIONS & ACTIVITIES: What are the people doing? What is happening?
   (e.g., "bonding and laughing together", "farming rice", "giving a speech")
3. SETTING & LOCATION: Where does this take place?
   (e.g., "outdoor farm", "school classroom", "rural barangay", "urban street")
4. EMOTIONS & MOOD: What emotions or mood is conveyed?
   (e.g., "joyful and celebratory", "solemn and reflective", "energetic")
5. NOTABLE OBJECTS or DETAILS: Any specific objects, animals, crops, clothing, or cultural elements?

Write a single detailed paragraph (4-6 sentences) in English.
Be specific about NUMBERS and GENDERS of people — this is critical for search.
Do NOT mention that these are video frames or thumbnails.
Do NOT start with "I" or "The frames show".
Just describe the visual content directly as if describing the scene.
''';

      final content = [
        Content.multi([
          TextPart(textPrompt),
          imagePart,
        ])
      ];

      final aiResponse = await model.generateContent(content).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('Visual analysis timed out.'),
      );

      final text = aiResponse.text;
      if (text != null && text.trim().isNotEmpty) {
        return text.trim();
      }
      return 'Visual analysis unavailable.';
    } catch (e) {
      debugPrint('Visual description error: $e');
      return 'Visual analysis unavailable: $e';
    }
  }
}
