import 'dart:convert';
import 'dart:io';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

Future<String> getAccessToken() async {
  final jsonString = File('assets/service_account.json').readAsStringSync();
  final credentials = ServiceAccountCredentials.fromJson(jsonString);
  final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
  final client = await clientViaServiceAccount(credentials, scopes);
  final accessToken = client.credentials.accessToken.data;
  client.close();
  return accessToken;
}

void main() async {
  try {
    print('Getting access token...');
    final token = await getAccessToken();
    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/my-flutter-app-e482c/messages:send');

    final payload = {
      'message': {
        'topic': 'new_uploads',
        'notification': {
          'title': 'Test Notification 🚀',
          'body': 'This is a test notification sent from Antigravity! Can you see this?',
        }
      }
    };

    print('Sending notification...');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      print('✅ Push notification sent successfully to topic new_uploads');
    } else {
      print('❌ Failed to send push notification: ${response.body}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}
