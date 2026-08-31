import 'dart:convert';
import 'dart:io';

void main() async {
  final apiKey = 'REMOVED_SECRET';
  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=\$apiKey');
  
  try {
    final client = HttpClient();
    final request = await client.getUrl(url);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    print(responseBody);
  } catch (e) {
    print('Error: \$e');
  }
}
