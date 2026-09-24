// Web-only implementation. Turns the raw bytes we already have in memory
// (from file_picker's withData: true on web) into a temporary
// "blob:https://...." URL the browser understands -- this is what lets
// CustomVideoPlayer's videoUrl/VideoPlayerController.networkUrl preview the
// file before it's even uploaded to Bunny.
import 'dart:html' as html;
import 'dart:typed_data';

String? createBlobUrl(List<int> bytes, String mimeType) {
  final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeBlobUrl(String url) {
  html.Url.revokeObjectUrl(url);
}
