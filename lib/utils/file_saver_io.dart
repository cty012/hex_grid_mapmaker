import 'dart:io';
import 'package:file_picker/file_picker.dart';

Future<void> saveFile(String filename, String content) async {
  final result = await FilePicker.saveFile(
    dialogTitle: 'Save map',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ['json'],
  );

  if (result != null) {
    final file = File(result);
    await file.writeAsString(content);
  }
}
