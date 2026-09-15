import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:cross_file/cross_file.dart';
import 'package:tus_client_dart/tus_client_dart.dart';
import '../env.dart';

class BunnyService {
  static const String _baseUrl = 'https://video.bunnycdn.com/library';

  /// Step 1: Create a video object in Bunny Stream and return its GUID.
  static Future<String> createVideoObject(String title) async {
    if (bunnyLibraryId == 'YOUR_LIBRARY_ID') {
      throw Exception('Bunny.net credentials not configured in env.dart');
    }

    final url = Uri.parse('$_baseUrl/$bunnyLibraryId/videos');
    
    final response = await http.post(
      url,
      headers: {
        'AccessKey': bunnyAccessKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'title': title}),
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception(
        'Bunny.net timed out after 30 seconds. Check your internet connection or API credentials.',
      ),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['guid'];
    } else {
      throw Exception('Failed to create video object: ${response.statusCode} - ${response.body}');
    }
  }

  static Future<void> uploadVideo(
    String guid,
    PlatformFile file, {
    Function(double progress)? onProgress,
  }) async {
    final expirationTime = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600; // 1 hour
    final dataToSign = '$bunnyLibraryId$bunnyAccessKey$expirationTime$guid';
    final signature = sha256.convert(utf8.encode(dataToSign)).toString();

    final headers = {
      'AuthorizationSignature': signature,
      'AuthorizationExpire': expirationTime.toString(),
      'VideoId': guid,
      'LibraryId': bunnyLibraryId,
    };

    final uri = Uri.parse('https://video.bunnycdn.com/tusupload');
    XFile xFile;

    if (kIsWeb) {
      if (file.bytes == null) throw Exception('No file bytes available on Web.');
      xFile = XFile.fromData(file.bytes!, name: file.name);
    } else {
      if (file.path == null) throw Exception('No file path available.');
      xFile = XFile(file.path!);
    }

    final client = TusClient(
      xFile,
      store: TusMemoryStore(),
      maxChunkSize: 10 * 1024 * 1024, // 10MB chunk
      retries: 5,
      retryInterval: 2,
    );

    await client.upload(
      uri: uri,
      headers: headers,
      onProgress: (double progress, Duration estimate) {
        if (onProgress != null) {
          onProgress(progress);
        }
      },
    );
  }

  /// Construct the Direct Play (HLS) URL
  static String getDirectPlayUrl(String guid) {
    return 'https://$bunnyPullZone/$guid/playlist.m3u8';
  }

  /// Construct the Thumbnail URL
  static String getThumbnailUrl(String guid) {
    return 'https://$bunnyPullZone/$guid/thumbnail.jpg';
  }

  /// Upload a custom thumbnail image directly to Bunny.net Stream
  static Future<void> uploadThumbnail(String guid, File imageFile) async {
    final url = Uri.parse('$_baseUrl/$bunnyLibraryId/videos/$guid/thumbnail');
    
    final bytes = await imageFile.readAsBytes();
    
    final response = await http.post(
      url,
      headers: {
        'AccessKey': bunnyAccessKey,
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to upload thumbnail to Bunny.net: ${response.statusCode} - ${response.body}');
    }
  }

  /// Delete a video from Bunny.net Stream (called when a film is deleted)
  static Future<void> deleteVideo(String guid) async {
    final url = Uri.parse('$_baseUrl/$bunnyLibraryId/videos/$guid');
    final response = await http.delete(
      url,
      headers: {
        'AccessKey': bunnyAccessKey,
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Failed to delete video from Bunny.net: ${response.statusCode} - ${response.body}');
    }
  }

  /// Check the encoding status of the video
  static Future<Map<String, dynamic>> getVideoStatus(String guid) async {
    final url = Uri.parse('$_baseUrl/$bunnyLibraryId/videos/$guid');
    final response = await http.get(
      url,
      headers: {
        'AccessKey': bunnyAccessKey,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'status': data['status'] as int,
        'encodeProgress': data['encodeProgress'] ?? 0,
      };
    }
    return {'status': -1, 'encodeProgress': 0}; // Unknown error
  }
}
