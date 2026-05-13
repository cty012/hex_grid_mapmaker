import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web implementation of file saving using the `package:web` API.
///
/// Creates an in-memory Blob from the content string, generates a temporary
/// object URL, programmatically clicks a hidden anchor element to trigger
/// the browser's download dialog, then revokes the URL to free memory.
Future<void> saveFile(String filename, String content) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
