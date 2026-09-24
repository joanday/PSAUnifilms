// Non-web fallback. Creating a browser "object URL" only makes sense
// inside an actual browser, so on mobile/desktop this just does nothing --
// submit_screen.dart never calls it there anyway (it's guarded by kIsWeb).

String? createBlobUrl(List<int> bytes, String mimeType) {
  return null;
}

void revokeBlobUrl(String url) {
  // no-op outside the browser
}
