/// Conditional export: web builds use dart:html, native builds use file_picker + dart:io.
export 'file_service_native.dart' if (dart.library.html) 'file_service_web.dart';
