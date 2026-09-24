import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import '../env.dart';

// ✅ FIXED: this used to upload through the `tus_client_dart` package, which
// has a bug where it sends the header "Tus-Resumable: 1.0" instead of the
// "1.0.0" that Bunny.net's TUS server requires -- Bunny then rejects every
// upload with "412 - Tus version 1.0 is not supported. Supported versions:
// 1.0.0". This replaces that package with our own minimal TUS 1.0.0 client
// built purely on package:http, so it works identically on web (Chrome/
// Edge) and on mobile -- no more silent "Something went wrong" errors.

class BunnyService {
  static const String _baseUrl = 'https://video.bunnycdn.com/library';
  static const String _tusUploadUrl = 'https://video.bunnycdn.com/tusupload';
  // ✅ CHANGED: this was 10MB per chunk, which meant that for any test
  // video smaller than 10MB, the ENTIRE file uploaded in a single chunk --
  // so the progress bar had nothing to show in between: it just sat at 0%
  // (indeterminate spinner) for the whole upload, then jumped straight to
  // 100% the instant it finished. That's almost certainly why no
  // percentage seemed to "appear" -- there was nothing gradual to see.
  // 2MB chunks mean even a small test video gets several progress
  // updates, so the bar actually visibly climbs.
  static const int _chunkSize = 2 * 1024 * 1024; // 2MB per chunk

  /// Step 1: Create a video object in Bunny Stream and return its GUID.
  static Future<String> createVideoObject(String title) async {
    if (bunnyLibraryId == 'YOUR_LIBRARY_ID') {
      throw Exception('Bunny.net credentials not configured in env.dart');
    }

    final url = Uri.parse('$_baseUrl/$bunnyLibraryId/videos');

    final response = await http
        .post(
          url,
          headers: {
            'AccessKey': bunnyAccessKey,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'title': title}),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception(
            'Bunny.net timed out after 30 seconds. Check your internet connection or API credentials.',
          ),
        );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['guid'];
    } else {
      throw Exception(
          'Failed to create video object: ${response.statusCode} - ${response.body}');
    }
  }

  /// Step 2: Upload the video bytes to Bunny.net using the TUS resumable
  /// upload protocol (v1.0.0), implemented by hand with package:http so it
  /// works the same way on web and on mobile/desktop.
  static Future<void> uploadVideo(
    String guid,
    String title,
    PlatformFile file, {
    Function(double progress)? onProgress,
    // ✅ NEW: fires with a short status message when a chunk has to be
    // retried, so the UI can show "Retrying... (attempt 2)" instead of
    // just looking stuck while that happens in the background.
    void Function(String message)? onStatus,
  }) async {
    final expirationTime =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600; // 1 hour
    final dataToSign = '$bunnyLibraryId$bunnyAccessKey$expirationTime$guid';
    final signature = sha256.convert(utf8.encode(dataToSign)).toString();

    final int totalSize = file.size;
    if (totalSize <= 0) {
      throw Exception('Selected file appears to be empty.');
    }

    // Bunny requires an Upload-Metadata header listing filetype + title,
    // each base64-encoded, comma-separated.
    final metadata = [
      'filetype ${base64.encode(utf8.encode(_guessMimeType(file.name)))}',
      'title ${base64.encode(utf8.encode(title))}',
    ].join(',');

    // Bunny requires these auth headers on every single request that
    // touches this upload -- not just the creation POST -- so the PATCH
    // chunk requests below need them too, or Bunny rejects them with
    // "400 - Library ID missing or invalid."
    final authHeaders = {
      'AuthorizationSignature': signature,
      'AuthorizationExpire': expirationTime.toString(),
      'VideoId': guid,
      'LibraryId': bunnyLibraryId,
    };

    final createResponse = await http.post(
      Uri.parse(_tusUploadUrl),
      headers: {
        ...authHeaders,
        'Tus-Resumable': '1.0.0',
        'Upload-Length': totalSize.toString(),
        'Upload-Metadata': metadata,
      },
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw Exception('Bunny.net upload initialization timed out.'),
    );

    if (createResponse.statusCode != 201) {
      throw Exception(
          'Failed to start upload: ${createResponse.statusCode} - ${createResponse.body}');
    }

    final location = createResponse.headers['location'];
    if (location == null || location.isEmpty) {
      throw Exception('Bunny.net did not return an upload location.');
    }
    final uploadUri = location.startsWith('http')
        ? Uri.parse(location)
        : Uri.parse(_tusUploadUrl).resolve(location);

    int offset = 0;

    if (kIsWeb) {
      // On web the file's bytes are already fully loaded in memory (see
      // submit_screen.dart's `withData: kIsWeb`), since there's no real
      // filesystem to stream from in the browser.
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes available on Web.');
      while (offset < totalSize) {
        final end =
            (offset + _chunkSize < totalSize) ? offset + _chunkSize : totalSize;
        final chunk = bytes.sublist(offset, end);
        offset = await _uploadChunkWithRetry(
            uploadUri, chunk, offset, authHeaders,
            onStatus: onStatus);
        onProgress?.call((offset / totalSize) * 100);
      }
    } else {
      // On mobile/desktop, stream chunks straight from disk instead of
      // loading the whole (potentially huge) video into memory.
      if (file.path == null) throw Exception('No file path available.');
      final raf = await File(file.path!).open();
      try {
        while (offset < totalSize) {
          final remaining = totalSize - offset;
          final thisChunkSize = remaining < _chunkSize ? remaining : _chunkSize;
          await raf.setPosition(offset);
          final chunk = await raf.read(thisChunkSize);
          offset = await _uploadChunkWithRetry(
              uploadUri, chunk, offset, authHeaders,
              onStatus: onStatus);
          onProgress?.call((offset / totalSize) * 100);
        }
      } finally {
        await raf.close();
      }
    }
  }

  // ✅ NEW: a single slow/dropped chunk used to fail the ENTIRE upload
  // immediately ("Upload chunk timed out"), even on an otherwise-fine
  // connection -- one bad moment and you'd have to start the whole video
  // over. This retries a timed-out or failed chunk up to 3 times (with a
  // short growing delay) before finally giving up, which is what TUS
  // resumable upload is meant to tolerate in the first place.
  static Future<int> _uploadChunkWithRetry(
    Uri uploadUri,
    List<int> chunk,
    int offset,
    Map<String, String> authHeaders, {
    void Function(String message)? onStatus,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _uploadChunk(uploadUri, chunk, offset, authHeaders);
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        debugPrint('Chunk upload attempt $attempt failed ($e), retrying...');
        onStatus?.call(
            'Connection hiccup -- retrying (attempt ${attempt + 1} of $maxAttempts)...');
        await Future.delayed(Duration(seconds: attempt * 3));
      }
    }
    // Unreachable -- the loop above always returns or rethrows.
    throw Exception('Chunk upload failed after $maxAttempts attempts.');
  }

  /// PATCHes a single chunk at the given offset and returns Bunny's
  /// confirmed new offset (falls back to the naive offset+chunk.length if
  /// the server doesn't echo one back).
  static Future<int> _uploadChunk(
    Uri uploadUri,
    List<int> chunk,
    int offset,
    Map<String, String> authHeaders,
  ) async {
    final response = await http
        .patch(
          uploadUri,
          headers: {
            ...authHeaders,
            'Tus-Resumable': '1.0.0',
            'Upload-Offset': offset.toString(),
            'Content-Type': 'application/offset+octet-stream',
          },
          body: chunk,
        )
        .timeout(
          // ✅ CHANGED: 90s -> 120s. A single slow chunk on a weaker connection
          // was hitting this timeout before it had a real chance to finish;
          // combined with the retry logic above, this gives a struggling
          // connection more breathing room before we give up on that chunk.
          const Duration(seconds: 120),
          onTimeout: () => throw Exception(
              'Upload chunk timed out -- check your internet connection.'),
        );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
          'Chunk upload failed: ${response.statusCode} - ${response.body}');
    }

    final newOffsetHeader = response.headers['upload-offset'];
    if (newOffsetHeader != null) {
      final parsed = int.tryParse(newOffsetHeader);
      if (parsed != null) return parsed;
    }
    return offset + chunk.length;
  }

  static String _guessMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
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
      throw Exception(
          'Failed to upload thumbnail to Bunny.net: ${response.statusCode} - ${response.body}');
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
