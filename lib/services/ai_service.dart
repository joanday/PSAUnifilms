import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
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
        model: 'gemini-flash-latest',
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
2. DO NOT guess the plot based on the title. You must heavily rely on the VIDEO TRANSCRIPT provided above to understand exactly what the video is about.
3. If the user's provided description is empty or too short, IGNORE IT and rely on the transcript and YouTube metadata.
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
}
