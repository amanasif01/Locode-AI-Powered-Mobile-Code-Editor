import codecs
import textwrap

path = r"d:\Locode\antigravity_ide\lib\presentation\editor_screen.dart"
with codecs.open(path, "r", "utf-8") as f:
    code = f.read()

# 1. Imports
code = code.replace("import 'widgets/code_editor.dart';", "import 'package:flutter_monaco/flutter_monaco.dart';\nimport '../domain/language_manager.dart';")
code = code.replace("import 'package:antigravity_ide/presentation/widgets/code_undo_manager.dart';", "")

# 2. State variables
code = code.replace(
    "  final Map<IDEFile, TextEditingController> _controllers = {};\n  final Map<IDEFile, CodeUndoManager> _undoManagers = {};\n  late final FocusNode _editorFocusNode;\n\n  TextEditingController get _codeController => _controllers[_openFiles[_activeFileIndex]]!;\n  CodeUndoManager get _undoManager => _undoManagers[_openFiles[_activeFileIndex]]!;",
    """  MonacoController? _monacoController;"""
)

# 3. onCodeChanged
old_onCodeChanged = """  void _onCodeChanged() {
    if (_activeFileIndex >= 0 && _activeFileIndex < _openFiles.length) {
      final file = _openFiles[_activeFileIndex];
      final prev = file.isDirty;
      file.content = _codeController.text;
      final newCount = _codeController.text.split('\\n').length;
      if (file.isDirty != prev || newCount != _lineCount) {
        setState(() => _lineCount = newCount < 1 ? 1 : newCount);
      }
    }
  }"""
new_onCodeChanged = """  void _onContentChanged(String newContent) {
    if (_activeFileIndex >= 0 && _activeFileIndex < _openFiles.length) {
      final file = _openFiles[_activeFileIndex];
      final prev = file.isDirty;
      file.content = newContent;
      LanguageManager.instance.getModelForExtension(file.extension).content = newContent;
      final newCount = newContent.split('\\n').length;
      if (file.isDirty != prev || newCount != _lineCount) {
        setState(() => _lineCount = newCount < 1 ? 1 : newCount);
      }
    }
  }

  void _loadActiveFileToMonaco() {
    if (_monacoController == null || _activeFileIndex == -1) return;
    final file = _openFiles[_activeFileIndex];
    final model = LanguageManager.instance.getModelForExtension(file.extension);
    // sync IDEFile content to model if needed
    model.content = file.content;
    
    _monacoController!.setLanguage(model.language);
    _monacoController!.setValue(model.content);
  }"""
code = code.replace(old_onCodeChanged, new_onCodeChanged)

# 4. dispose
code = code.replace("""  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.removeListener(_onCodeChanged);
      c.dispose();
    }
    for (final u in _undoManagers.values) {
      u.dispose();
    }
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }""", """  @override
  void dispose() {
    _editorScrollController.dispose();
    super.dispose();
  }""")

# 5. _openFile
code = code.replace("""    setState(() {
      _openFiles.add(file);
      _activeFileIndex = _openFiles.length - 1;
      _codeController.text = file.content;
    });""", """    setState(() {
      _openFiles.add(file);
      _activeFileIndex = _openFiles.length - 1;
    });
    _loadActiveFileToMonaco();""")

# 6. _createNewFile
code = code.replace("""  void _createNewFile(String name, String ext) {
    setState(() {
      final newFile = IDEFile(name: name, extension: ext);
      final c = TextEditingController()..addListener(_onCodeChanged);
      _controllers[newFile] = c;
      _undoManagers[newFile] = CodeUndoManager(controller: c);
      _openFiles.add(newFile);
      _activeFileIndex = _openFiles.length - 1;
      _lineCount = 1;
    });
  }""", """  void _createNewFile(String name, String ext) {
    setState(() {
      final newFile = IDEFile(name: name, extension: ext);
      _openFiles.add(newFile);
      _activeFileIndex = _openFiles.length - 1;
      _lineCount = 1;
    });
    _loadActiveFileToMonaco();
  }""")

# _runCode
code = code.replace("""    compilerService.runCode(
        _controllers[_openFiles[_activeFileIndex]]!.text, _openFiles[_activeFileIndex].extension);""", """    compilerService.runCode(
        _openFiles[_activeFileIndex].content, _openFiles[_activeFileIndex].extension);""")

# _moveCursor (delete it or empty it)
code = code.replace("""  void _moveCursor(int offset) {
    if (!_editorFocusNode.hasFocus) _editorFocusNode.requestFocus();
    final controller = _controllers[_openFiles[_activeFileIndex]]!;
    int cur = controller.selection.baseOffset;
    if (cur < 0) cur = controller.text.length;
    controller.selection = TextSelection.collapsed(
        offset: (cur + offset).clamp(0, controller.text.length));
  }""", """  void _moveCursor(int offset) {
    // Monaco handles its own keyboard navigation natively, no arrow overlay needed.
  }""")

# _selectTab
code = code.replace("""  void _selectTab(int index) {
    setState(() {
      _activeFileIndex = index;
      _lineCount = _controllers[_openFiles[index]]!.text.split('\\n').length;
    });
  }""", """  void _selectTab(int index) {
    setState(() {
      _activeFileIndex = index;
      _lineCount = _openFiles[index].content.split('\\n').length;
    });
    _loadActiveFileToMonaco();
  }""")

# _forceCloseTab
code = code.replace("""  void _forceCloseTab(int index) {
    setState(() {
      final file = _openFiles[index];
      _openFiles.removeAt(index);
      
      _controllers[file]?.removeListener(_onCodeChanged);
      _controllers[file]?.dispose();
      _undoManagers[file]?.dispose();
      _controllers.remove(file);
      _undoManagers.remove(file);

      if (_openFiles.isEmpty) {
        _activeFileIndex = -1;
      } else {
        _activeFileIndex =
            index >= _openFiles.length ? _openFiles.length - 1 : index;
        _lineCount = _controllers[_openFiles[_activeFileIndex]]!.text.split('\\n').length;
      }
    });
  }""", """  void _forceCloseTab(int index) {
    setState(() {
      _openFiles.removeAt(index);
      if (_openFiles.isEmpty) {
        _activeFileIndex = -1;
      } else {
        _activeFileIndex =
            index >= _openFiles.length ? _openFiles.length - 1 : index;
        _lineCount = _openFiles[_activeFileIndex].content.split('\\n').length;
      }
    });
    if (_activeFileIndex != -1) _loadActiveFileToMonaco();
  }""")

# Undo/Redo Buttons
code = code.replace("""                    // ── Undo / Redo ──
                    ValueListenableBuilder<bool>(
                      valueListenable: _undoManagers[_openFiles[_activeFileIndex]]!.canUndo,
                      builder: (context, canUndo, _) {
                        return IconButton(
                          icon: const Icon(Icons.undo_rounded, size: 20),
                          onPressed: canUndo ? () => _undoManagers[_openFiles[_activeFileIndex]]!.undo() : null,
                          tooltip: 'Undo',
                          splashRadius: 20,
                          color: canUndo ? textPrimary : textMuted.withOpacity(0.5),
                        );
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _undoManagers[_openFiles[_activeFileIndex]]!.canRedo,
                      builder: (context, canRedo, _) {
                        return IconButton(
                          icon: const Icon(Icons.redo_rounded, size: 20),
                          onPressed: canRedo ? () => _undoManagers[_openFiles[_activeFileIndex]]!.redo() : null,
                          tooltip: 'Redo',
                          splashRadius: 20,
                          color: canRedo ? textPrimary : textMuted.withOpacity(0.5),
                        );
                      },
                    ),""", """                    // ── Undo / Redo ──
                    IconButton(
                      icon: const Icon(Icons.undo_rounded, size: 20),
                      onPressed: () => _monacoController?.undo(),
                      tooltip: 'Undo',
                      splashRadius: 20,
                      color: textPrimary,
                    ),
                    IconButton(
                      icon: const Icon(Icons.redo_rounded, size: 20),
                      onPressed: () => _monacoController?.redo(),
                      tooltip: 'Redo',
                      splashRadius: 20,
                      color: textPrimary,
                    ),""")

# Editor Area -> Remove CodeEditorWithGutter and Arrow navigation.
old_editor_area = """                        // ── CodeEditorWithGutter (pixel-perfect alignment) ──
                        Positioned.fill(
                          child: CodeEditorWithGutter(
                            controller: _controllers[_openFiles[_activeFileIndex]]!,
                            focusNode: _editorFocusNode,
                            scrollController: _editorScrollController,
                          ),
                        ),
                        // Arrow nav
                        Positioned(
                          bottom: 16.0,
                          right: 16.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF05050A).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: cyanAccent.withOpacity(0.2)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.6),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _moveCursor(-1),
                                  child: const Padding(
                                    padding: EdgeInsets.all(10.0),
                                    child: Icon(Icons.arrow_left_rounded,
                                        color: Color(0xFF00FFFF), size: 28),
                                  ),
                                ),
                                Container(
                                    width: 1,
                                    height: 20,
                                    color: borderNeon),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _moveCursor(1),
                                  child: const Padding(
                                    padding: EdgeInsets.all(10.0),
                                    child: Icon(Icons.arrow_right_rounded,
                                        color: Color(0xFF00FFFF), size: 28),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),"""

new_editor_area = """                        Positioned.fill(
                          child: MonacoEditor(
                            onReady: (controller) {
                              _monacoController = controller;
                              _loadActiveFileToMonaco();
                            },
                            onContentChanged: _onContentChanged,
                            options: const EditorOptions(
                              theme: MonacoTheme.vsDark,
                              fontSize: 15,
                            ),
                          ),
                        ),"""
code = code.replace(old_editor_area, new_editor_area)

# _openSelectedRecent
code = code.replace("""          setState(() {
            final c = TextEditingController(text: file.content)..addListener(_onCodeChanged);
            _controllers[file] = c;
            _undoManagers[file] = CodeUndoManager(controller: c);
            _openFiles.add(file);
            _activeFileIndex = _openFiles.length - 1;
          });""", """          setState(() {
            _openFiles.add(file);
            _activeFileIndex = _openFiles.length - 1;
          });
          _loadActiveFileToMonaco();""")

with codecs.open(path, "w", "utf-8") as f:
    f.write(code)

print("Done replacing.")
