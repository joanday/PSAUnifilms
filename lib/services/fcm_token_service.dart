import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<String> getAccessToken() async {
  // Load the service account JSON file from assets
  final jsonString = await rootBundle.loadString('assets/service_account.json');

  // Convert it into credentials googleapis_auth understands
  final credentials = ServiceAccountCredentials.fromJson(jsonString);

  // This scope allows sending messages via FCM
  final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  // Authenticate and get a client with a valid access token
  final client = await clientViaServiceAccount(credentials, scopes);

  // Extract just the token string
  final accessToken = client.credentials.accessToken.data;

  client.close();

  return accessToken;
}

Future<bool> sendApprovalNotification(String filmTitle) async {
  try {
    final token = await getAccessToken();
    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/my-flutter-app-e482c/messages:send');

    final payload = {
      'message': {
        'topic': 'new_uploads',
        'notification': {
          'title': 'New Documentary Approved! 🎬',
          'body': '"$filmTitle" is now available to watch!',
        }
      }
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      debugPrint('✅ Push notification sent successfully via client');
      return true;
    } else {
      debugPrint('❌ Failed to send push notification: ${response.body}');
      return false;
    }
  } catch (e) {
    debugPrint('❌ Error sending push notification: $e');
    return false;
  }
}

Future<bool> sendReturnNotification(String uploaderId, String filmTitle, String note) async {
  try {
    final token = await getAccessToken();
    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/my-flutter-app-e482c/messages:send');

    final payload = {
      'message': {
        'topic': 'user_$uploaderId',
        'notification': {
          'title': 'Documentary Returned 🔙',
          'body': 'Your submission "$filmTitle" has been returned. Note: $note',
        }
      }
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      debugPrint('✅ Return notification sent successfully');
      return true;
    } else {
      debugPrint('❌ Failed to send return notification: ${response.body}');
      return false;
    }
  } catch (e) {
    debugPrint('❌ Error sending return notification: $e');
    return false;
  }
}
