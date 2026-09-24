// Picks the right implementation automatically:
// - in a real browser (flutter run -d chrome / a deployed web build),
//   dart.library.html exists, so blob_url_web.dart is used.
// - on Android/iOS/desktop, blob_url_stub.dart is used instead.
// submit_screen.dart just imports this one file and doesn't need to care
// which platform it's running on.
export 'blob_url_stub.dart' if (dart.library.html) 'blob_url_web.dart';
