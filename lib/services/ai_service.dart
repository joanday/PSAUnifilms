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

  static Future<AiMetadata> generateMetadata(String title, String description) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-flash-latest',
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
      print('Falling back to mock metadata due to API restrictions.');
      return AiMetadata(
        summary: 'A compelling film exploring themes of $title. (Mock AI Summary due to API restriction)',
        keywords: [title.split(' ').first, 'Indie', 'Student Film', 'Project', 'Creative'],
      );
    }
    throw Exception('AI returned an empty response.');
  }
}
