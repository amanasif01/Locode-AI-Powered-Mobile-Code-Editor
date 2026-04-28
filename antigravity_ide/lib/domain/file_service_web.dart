// Web implementation of FileService using dart:html
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';

class FileService {
  static const _allowedExtensions = ['py', 'cpp', 'js'];

  static Future<({String path, String name, String ext, String content})?> openFile() {
    final completer = Completer<({String path, String name, String ext, String content})?>();
    final input = html.FileUploadInputElement()
      ..accept = _allowedExtensions.map((e) => '.$e').join(',');

    input.onChange.listen((_) async {
      if (input.files == null || input.files!.isEmpty) {
        completer.complete(null);
        return;
      }
      final file = input.files!.first;
      final parts = file.name.split('.');
      if (parts.length < 2) { completer.complete(null); return; }
      final ext = parts.last.toLowerCase();
      if (!_allowedExtensions.contains(ext)) { completer.complete(null); return; }
      final baseName = parts.sublist(0, parts.length - 1).join('.');
      final reader = html.FileReader()..readAsText(file);
      reader.onLoad.listen((_) => completer.complete((path: '', name: baseName, ext: ext, content: reader.result as String)));
      reader.onError.listen((_) => completer.complete(null));
    });
    input.click();
    return completer.future;
  }

  /// Web: always downloads — no directory picker available in browser sandbox.
  static Future<void> saveFile(String filename, String content, {String? directory}) async {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], 'text/plain');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Web: picks new name, then downloads.
  static Future<String?> pickSaveDirectory() async => null; // Not supported on web
}
