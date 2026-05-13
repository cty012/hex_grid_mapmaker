// Platform-conditional export for file saving.
//
// Uses Dart's conditional import to select the right implementation:
// - Web: file_saver_web.dart — creates a Blob and triggers a download.
// - Desktop/Mobile: file_saver_io.dart — writes to the local filesystem.
// - Unsupported: file_saver_stub.dart — throws UnsupportedError.
export 'file_saver_stub.dart'
  if (dart.library.html) 'file_saver_web.dart'
  if (dart.library.io) 'file_saver_io.dart';
