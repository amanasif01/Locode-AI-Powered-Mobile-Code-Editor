import 'package:flutter_monaco/flutter_monaco.dart';

class MonacoTextModel {
  String content;
  final MonacoLanguage language;

  MonacoTextModel({
    required this.language,
    this.content = '',
  });
}

class LanguageManager {
  static final LanguageManager instance = LanguageManager._internal();

  LanguageManager._internal() {
    _models['py'] = MonacoTextModel(language: MonacoLanguage.python);
    _models['cpp'] = MonacoTextModel(language: MonacoLanguage.cpp);
    _models['c'] = MonacoTextModel(language: MonacoLanguage.c);
  }

  final Map<String, MonacoTextModel> _models = {};

  MonacoTextModel getModelForExtension(String extension) {
    if (_models.containsKey(extension)) {
      return _models[extension]!;
    }
    // Fallback for unsupported extensions
    return MonacoTextModel(language: MonacoLanguage.plaintext);
  }
}
