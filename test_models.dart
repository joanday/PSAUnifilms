
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lib/env.dart';

void main() async {
  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=' + geminiApiKey);
  final response = await http.get(url);
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final models = data['models'] as List;
    for (var model in models) {
      print(model['name']);
    }
  } else {
    print('Failed: ' + response.body);
  }
}

