import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../env.dart';

class AiMetadata {
  final String summary;
  final List<String> keywords;

  AiMetadata({required this.summary, required this.keywords});
}

class AiService {
  // Loaded from env.dart to protect secrets from GitHub
  static const String _apiKey = geminiApiKey;

  static Future<AiMetadata?> generateMetadata(String title, String description) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
      );

      final prompt = '''
You are an AI video analysis tool for a university documentary platform.
Analyze the following documentary details:
Title: "$title"
Description: "$description"

Please generate two things based on this information:
1. A highly professional, slightly expanded summary (3-4 sentences max) describing the themes and potential impact of this documentary.
2. A list of 5 to 8 highly relevant searchable keywords/tags that describe the concepts in this film.

Format your response exactly as JSON like this:
{
  "summary": "Your professional summary here...",
  "keywords": ["keyword1", "keyword2", "keyword3"]
}
''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      final text = response.text;
      if (text != null) {
        // Strip markdown code blocks if the AI wraps the JSON
        final cleanText = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final Map<String, dynamic> data = jsonDecode(cleanText);
        
        return AiMetadata(
          summary: data['summary'] ?? '',
          keywords: List<String>.from(data['keywords'] ?? []),
        );
      }
    } catch (e) {
      print('AI Service Error: $e');
    }
    return null;
  }
}
