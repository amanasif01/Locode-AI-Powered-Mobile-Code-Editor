import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class RecentFileEntry {
  final String path;   // Full disk path (empty on web)
  final String name;
  final String ext;
  final DateTime lastOpened;

  RecentFileEntry({
    required this.path,
    required this.name,
    required this.ext,
    required this.lastOpened,
  });

  String get fullName => '$name.$ext';

  bool get existsOnDisk {
    if (kIsWeb || path.isEmpty) return false;
    return io.File(path).existsSync();
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'ext': ext,
    'lastOpened': lastOpened.toIso8601String(),
  };

  factory RecentFileEntry.fromJson(Map<String, dynamic> j) => RecentFileEntry(
    path: j['path'] as String,
    name: j['name'] as String,
    ext: j['ext'] as String,
    lastOpened: DateTime.parse(j['lastOpened'] as String),
  );
}

class RecentFilesService {
  static const _key = 'locode_recent_files';
  static const _maxEntries = 5;

  /// Load all recent entries, filtering out files that no longer exist on disk.
  static Future<List<RecentFileEntry>> loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3), onTimeout: () => throw Exception('timeout'));
      final raw = prefs.getStringList(_key) ?? [];
      final entries = raw
          .map((e) {
            try { return RecentFileEntry.fromJson(jsonDecode(e)); }
            catch (_) { return null; }
          })
          .whereType<RecentFileEntry>()
          .toList();

      if (!kIsWeb) {
        return entries.where((e) => e.existsOnDisk).toList();
      }
      return entries;
    } catch (_) {
      return []; // Timeout or error — just return empty list
    }
  }

  /// Record a newly opened/saved file at the top of the recent list.
  static Future<void> addRecent(String path, String name, String ext) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadRecent();

    // Remove any duplicate entry for the same path
    existing.removeWhere((e) => e.path == path);

    final updated = [
      RecentFileEntry(path: path, name: name, ext: ext, lastOpened: DateTime.now()),
      ...existing,
    ].take(_maxEntries).toList();

    await prefs.setStringList(_key, updated.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> clearRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
