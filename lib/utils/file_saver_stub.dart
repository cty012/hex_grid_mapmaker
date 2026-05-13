/// Stub implementation used when no platform-specific file saver is available.
Future<void> saveFile(String filename, String content) async {
  throw UnsupportedError('Cannot save file on this platform');
}
