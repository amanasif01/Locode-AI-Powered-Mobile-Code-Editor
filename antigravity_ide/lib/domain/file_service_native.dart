// Native (Android/iOS/Desktop) implementation of FileService
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class FileService {
  static const _allowedExtensions = ['py', 'cpp', 'js'];

  /// Opens the system file picker filtered to code files.
  static Future<({String path, String name, String ext, String content})?> openFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    if (picked.path == null) return null;

    final file = File(picked.path!);
    final String content = await file.readAsString();
    final parts = picked.name.split('.');
    final String ext = parts.last.toLowerCase();
    final String name = parts.sublist(0, parts.length - 1).join('.');

    // Copy to persistent storage so it survives restarts
    final docDir = await getApplicationDocumentsDirectory();
    final persistentFile = File('${docDir.path}/${picked.name}');
    await persistentFile.writeAsString(content, flush: true);

    return (path: persistentFile.path, name: name, ext: ext, content: content);
  }

  /// Saves to [directory]/[filename], or falls back to app Documents dir.
  static Future<void> saveFile(String pathOrFilename, String content,
      {String? directory}) async {
    File file;
    if (pathOrFilename.contains('/') || pathOrFilename.contains('\\')) {
      file = File(pathOrFilename);
    } else {
      final dir = directory != null
          ? Directory(directory)
          : await getApplicationDocumentsDirectory();
      file = File('${dir.path}/$pathOrFilename');
    }
    await file.writeAsString(content, flush: true);
  }

  /// Opens an OS directory picker. Returns the chosen path, or null if cancelled.
  static Future<String?> pickSaveDirectory() async {
    return await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where to save',
      lockParentWindow: true,
    );
  }
}
