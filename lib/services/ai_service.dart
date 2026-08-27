import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../env.dart';

class AiMetadata {
  final String summary;
  final List<String> keywords;

  AiMetadata({required this.summary, required this.keywords});
}

class AiService {
  // Loaded from env.dart to protect secrets from GitHub
  static const String _apiKey = geminiApiKey;

  static Future<AiMetadata> generateMetadata(String title, String description, {String? youtubeId}) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: _apiKey,
      );

      String actualTitle = title;
      String actualDescription = description;
      String transcriptText = "No transcript available.";

      if (youtubeId != null && youtubeId.isNotEmpty) {
        try {
          final yt = YoutubeExplode();
          final video = await yt.videos.get(youtubeId);
          actualTitle = video.title;
          actualDescription = video.description;
          
          try {
            final manifest = await yt.videos.closedCaptions.getManifest(youtubeId);
            if (manifest.tracks.isNotEmpty) {
              // Prioritize Tagalog/Filipino/English, otherwise grab the first available
              final trackInfo = manifest.getByLanguage('tl').firstOrNull ?? 
                                manifest.getByLanguage('fil').firstOrNull ?? 
                                manifest.getByLanguage('en').firstOrNull ?? 
                                manifest.tracks.first;
                                
              final track = await yt.videos.closedCaptions.get(trackInfo);
              transcriptText = track.captions.map((e) => e.text).join(' ');
              
              // Truncate to avoid exceeding token limits
              if (transcriptText.length > 30000) {
                transcriptText = '${transcriptText.substring(0, 30000)}... (truncated)';
              }
            }
          } catch (e) {
            print('No closed captions found: $e');
          }
          
          yt.close();
        } catch (e) {
          print('Error fetching YouTube metadata: $e');
        }
      }

      final prompt = '''
You are an expert AI video analysis tool for a university documentary platform in the Philippines.
Your task is to provide an accurate summary and keywords for a documentary.

The user provided the following details:
Title: "$title"
Description: "$description"

We also pulled the exact metadata and transcript from YouTube for this video:
Actual YouTube Title: "$actualTitle"
Actual YouTube Description: "$actualDescription"

VIDEO TRANSCRIPT / CAPTIONS:
"""
$transcriptText
"""

IMPORTANT INSTRUCTIONS:
1. The transcript may be in Tagalog, Kapampangan, or English. You are fully capable of understanding these languages.
2. If a transcript is available, rely on it to understand what the video is about.
3. If the transcript says "No transcript available.", DO NOT write an error message or complain about missing data. Instead, generate the best possible professional summary and keywords based purely on the Title and Description. Under NO circumstances should you say a summary cannot be generated.
4. Generate a highly professional, accurate summary (3-4 sentences max) in ENGLISH describing the true themes, cultural relevance, and potential impact of this documentary based on its spoken content.
5. Generate a list of 5 to 8 highly relevant searchable keywords/tags (these can be English, Tagalog, or Kapampangan) that describe the actual concepts discussed in the video.

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
      print('API Error: $e');
      return AiMetadata(
        summary: 'API ERROR: $e',
        keywords: ['Error'],
      );
    }
    throw Exception('AI returned an empty response.');
  }

  /// True CBVR: analyzes actual video frames using Gemini Vision.
  ///
  /// Fetches 3 auto-generated YouTube frame thumbnails (at ~25%, 50%, 75%
  /// of the video) and sends them to gemini-2.0-flash as images.
  /// Gemini Vision then describes the visual content in detail:
  /// number of people, genders, activities, setting, emotions, objects.
  ///
  /// This lets CBVR find films by visual content even when nothing
  /// is written in the description or summary.
  static Future<String> generateVisualDescription(String youtubeId) async {
    try {
      // YouTube auto-generates 3 frame captures at roughly 25%, 50%, 75%
      final frameUrls = [
        'https://img.youtube.com/vi/$youtubeId/1.jpg',
        'https://img.youtube.com/vi/$youtubeId/2.jpg',
        'https://img.youtube.com/vi/$youtubeId/3.jpg',
      ];

      // Fetch all frames in parallel
      final futures = frameUrls.map((url) => http.get(Uri.parse(url)));
      final responses = await Future.wait(futures);

      // Build image parts for Gemini Vision (only include successful fetches)
      final imageParts = <DataPart>[];
      for (final response in responses) {
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          imageParts.add(DataPart('image/jpeg', response.bodyBytes));
        }
      }

      if (imageParts.isEmpty) {
        return 'Visual analysis unavailable: could not fetch video frames.';
      }

      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
      );

      const textPrompt = '''
You are a visual content analyzer for a Philippine university documentary platform.
You are given frame captures from a documentary video.

Analyze the frames carefully and provide a comprehensive visual description.
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
          ...imageParts,
        ])
      ];

      final response = await model.generateContent(content).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('Visual analysis timed out.'),
      );

      final text = response.text;
      if (text != null && text.trim().isNotEmpty) {
        return text.trim();
      }
      return 'Visual analysis unavailable.';
    } catch (e) {
      print('Visual description error: $e');
      return 'Visual analysis unavailable: $e';
    }
  }
}
