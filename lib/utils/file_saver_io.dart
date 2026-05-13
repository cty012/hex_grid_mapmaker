import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// Returns true if the file was saved, false if the user cancelled.
Future<bool> saveFile(String filename, String content) async {
  final result = await FilePicker.saveFile(
    dialogTitle: 'Save map',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ['json'],
  );

  if (result != null) {
    final file = File(result);
    await file.writeAsString(content);
    return true;
  }
  return false;
}
