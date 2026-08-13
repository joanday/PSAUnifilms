
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lib/env.dart';

void main() async {
  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=' + geminiApiKey);
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'contents': [
        {
          'parts': [{'text': 'Generate a simple JSON object'}]
        }
      ]
    })
  );
  print(response.statusCode);
  print(response.body);
}

