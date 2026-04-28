class IDEFile {
  final String name;
  final String extension;
  String? absolutePath;
  String content;

  /// The content at the point the file was last saved to disk.
  /// null = file has never been saved.
  String? _savedContent;

  IDEFile({
    required this.name,
    required this.extension,
    this.content = '',
    this.absolutePath,
  });

  String get fullName => '$name.$extension';

  /// True when in-memory content differs from the last saved snapshot.
  bool get isDirty => content != _savedContent;

  /// Call this after a successful disk write.
  void markSaved() => _savedContent = content;
}
