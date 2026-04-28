import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/compiler_service.dart';
import '../domain/ide_file.dart';
import '../domain/file_service.dart';
import '../domain/recent_files_service.dart';
import 'widgets/terminal_panel.dart';
import 'widgets/editor_header.dart';
import 'widgets/editor_tab_bar.dart';
import 'widgets/editor_status_bar.dart';
import 'widgets/editor_dock.dart';
import 'widgets/locode_ai_panel.dart';
import '../domain/language_manager.dart';
import 'dart:io' as io; // Use alias to prevent accidental usage
import 'package:flutter/foundation.dart' show kIsWeb;
import '../domain/diff_parser.dart';
import '../domain/settings_service.dart';

import 'widgets/modern_terminal.dart';
import '../domain/terminal_controller.dart';
import 'widgets/native_code_editor.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late LocodeNativeController _nativeController;
  final FocusNode _editorFocusNode = FocusNode();

  List<IDEFile> _openFiles = [];
  List<RecentFileEntry> _recentFiles = [];
  final Set<int> _selectedRecent = {};
  int _activeFileIndex = -1;
  bool get hasActiveFile => _activeFileIndex >= 0 && _activeFileIndex < _openFiles.length;

  final TerminalController _terminalController = TerminalController();
  String _latestOutput = "Initializing Engine...";
  bool _isTerminalOpen = false;
  bool _isRunning = false;
  bool _isDarkMode = true;
  bool _isLocodeAiOpen = false;
  int _openDialogsCount = 0;
  bool _isSelectionMode = false;
  bool _isPythonOnline = false;

  void _toggleSelectionMode() {
    setState(() => _isSelectionMode = !_isSelectionMode);
    if (!_isSelectionMode) {
      _editorFocusNode.requestFocus();
    }
  }

  // Online (Llama) pending change proposal state
  _AiEditPlan? _pendingAiPlan;
  String? _pendingAiCandidate;
  List<_LineDiff> _pendingAiLineDiff = const [];
  bool _blockEditorInteractionForReview = false;
  String? _queuedAiSuggestion;

  // Diff / Precision Editing State
  // Each active diff block tracks: original search text, inserted line range for replacement

  Future<T?> _showDialogGuarded<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    setState(() => _openDialogsCount++);
    final result = await showDialog<T>(context: context, builder: builder);
    if (mounted) setState(() => _openDialogsCount--);
    return result;
  }

  // Gutter / scroll state
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();
  int _lineCount = 1;

  // ── Init / Dispose ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _editorScrollController.addListener(() {
      if (_gutterScrollController.hasClients && _editorScrollController.hasClients) {
        _gutterScrollController.jumpTo(_editorScrollController.offset);
      }
    });
    _nativeController = LocodeNativeController(
      language: 'cpp',
      styles: {
        'comment':  const TextStyle(color: Color(0xFF5C6370), fontStyle: FontStyle.italic),
        'string':   const TextStyle(color: Color(0xFF98C379)),
        'keyword':  const TextStyle(color: Color(0xFFC678DD), fontWeight: FontWeight.bold),
        'type':     const TextStyle(color: Color(0xFFE5C07B)),
        'function': const TextStyle(color: Color(0xFF61AFEF)),
        'number':   const TextStyle(color: Color(0xFFD19A66)),
        'bracket':  const TextStyle(color: Color(0xFF56B6C2), fontWeight: FontWeight.bold),
        'operator': const TextStyle(color: Color(0xFFABB2BF)),
        'variable': const TextStyle(color: Color(0xFFE06C75)),
      },
    );
    _nativeController.addListener(() {
      _onContentChanged(_nativeController.text);
    });

    compilerService.init();
    compilerService.setTerminalController(_terminalController);
    compilerService.outputStream.listen((msg) {
      if (mounted) {
        setState(() => _latestOutput = msg);
        _terminalController.addOutput(msg);
        _highlightErrorLines(msg);
      }
    });
    compilerService.runningStream.listen((running) {
      if (mounted) setState(() => _isRunning = running);
    });
    _loadRecentFiles();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDark = await SettingsService.isDarkMode();
    if (mounted) setState(() => _isDarkMode = isDark);
  }

  Future<void> _loadRecentFiles() async {
    final recent = await RecentFilesService.loadRecent();
    if (mounted) setState(() => _recentFiles = recent);
  }

  void _onContentChanged(String newContent) {
    if (hasActiveFile) {
      final file = _openFiles[_activeFileIndex];
      file.content = newContent;
      LanguageManager.instance.getModelForExtension(file.extension).content = newContent;
      final newCount = newContent.split('\n').length;
      final actualNewCount = newCount < 1 ? 1 : newCount;
      if (actualNewCount != _lineCount) {
        setState(() => _lineCount = actualNewCount);
      }
    }
  }

  /// Parses [output] for error line numbers and highlights them red in Monaco.
  /// Only runs when the output contains clear error/exception indicators.
  void _highlightErrorLines(String output) {
    // Native highlighting can be implemented here by adding to the controller styles
    final lower = output.toLowerCase();
    final hasError = lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('traceback') ||
        lower.contains('syntaxerror') ||
        lower.contains('nameerror') ||
        lower.contains('typeerror') ||
        lower.contains('valueerror') ||
        lower.contains('indexerror') ||
        lower.contains('attributeerror') ||
        lower.contains('failed') ||
        lower.contains('undefined') ||
        lower.contains('uncaught');

    if (!hasError) {
      // _monacoController!.clearDecorations();
      return;
    }

    final lineNums = <int>{};
    final patterns = [
      RegExp(r'[Ll]ine (\d+)'),                      // line 5
      RegExp(r', line (\d+)'),                        // , line 5  (Python tracebacks)
      RegExp(r':(\d+):\d+'),                          // :5:10  (JS / compiler style)
      RegExp(r'^.+\.(?:py|js|dart|cpp|java|c):(\d+)', multiLine: true), // file.py:5
    ];

    for (final pattern in patterns) {
      for (final m in pattern.allMatches(output)) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null && n > 0 && n < 50000) lineNums.add(n);
      }
    }

    if (lineNums.isEmpty) return;

    // Monaco decorations removed since we're using Native controller
    /*
    final decorations = lineNums.map((line) =>
      DecorationOptions.line(
        range: Range.singleLine(line),
        className: 'locode-error-line',
        additionalOptions: const {'linesDecorationsClassName': 'locode-error-margin'},
      ),
    ).toList();

    _monacoController!.setDecorations(decorations);
    */
  }

  void _loadActiveFileToEditor() {
    if (_activeFileIndex == -1) return;
    final file = _openFiles[_activeFileIndex];

    _nativeController.language = file.extension;
    _nativeController.text = file.content;
    _nativeController.clearUndoHistory();
    setState(() {
      _lineCount = file.content.split('\n').length;
      if (_lineCount < 1) _lineCount = 1;
      _pendingAiPlan = null;
      _pendingAiCandidate = null;
      _pendingAiLineDiff = const [];
      _blockEditorInteractionForReview = false;
    });
  }

  void _ensureActiveFileForAi() {
    if (hasActiveFile) return;
    setState(() {
      final newFile = IDEFile(name: 'llama_suggestion', extension: 'txt', content: '');
      _openFiles.add(newFile);
      _activeFileIndex = _openFiles.length - 1;
      _lineCount = 1;
    });
    _loadActiveFileToEditor();
  }

  @override
  void dispose() {
    _editorScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  // ── File Operations ────────────────────────────────────────────────────────

  void _showFileMenu() {
    _showDialogGuarded(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1A1A24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.now_widgets_rounded,
                    color: Color(0xFF00FFFF), size: 18),
                SizedBox(width: 8),
                Text('LOCODE FILES',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0)),
              ]),
              const SizedBox(height: 28),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _fileMenuAction(
                      icon: Icons.folder_open_rounded,
                      label: 'Open File',
                      color: const Color(0xFF00FFFF),
                      onTap: () {
                        Navigator.pop(context);
                        _showOpenDialog();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _fileMenuAction(
                      icon: Icons.add_circle_outline_rounded,
                      label: 'New File',
                      color: const Color(0xFF9D00FF),
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateDialog();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFile() async {
    final result = await FileService.openFile();
    if (result == null) return;
    final file = IDEFile(name: result.name, extension: result.ext, content: result.content);
    file.markSaved();
    // Record in recents — on Android result.path will be the full disk path
    await RecentFilesService.addRecent(result.path, result.name, result.ext);
    if (!mounted) return;
    setState(() {
      _openFiles.add(file);
      _activeFileIndex = _openFiles.length - 1;
    });
    _loadActiveFileToEditor();
  }

  Future<void> _showOpenDialog() async {
    await _loadRecentFiles();
    if (!mounted) return;
    _showDialogGuarded(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1A1A24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.folder_open_rounded, color: Color(0xFF00FFFF), size: 18),
                   SizedBox(width: 8),
                   Text('OPEN FILE', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
                ]
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFF00FFFF).withOpacity(0.15),
                    side: const BorderSide(color: Color(0xFF00FFFF)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.sd_storage_rounded, color: Color(0xFF00FFFF), size: 18),
                  label: const Text('BROWSE DEVICE STORAGE', style: TextStyle(color: Color(0xFF00FFFF), fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openFile();
                  },
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('RECENT FILES', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5))
              ),
              const SizedBox(height: 12),
              if (_recentFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No recent files found.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                )
              else
                ..._recentFiles.map((rf) => GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    _openSingleRecent(rf);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A24).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF333344)),
                    ),
                    child: Row(children: [
                      Icon(Icons.insert_drive_file_rounded, size: 16, color: const Color(0xFF00FFFF).withOpacity(0.5)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(rf.fullName, style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'))),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
                    ]),
                  ),
                )).toList(),
            ],
          )
        )
      )
    );
  }

  Future<void> _openSingleRecent(RecentFileEntry entry) async {
    if (kIsWeb) {
      _showSnack('Cannot load disk paths on Web. Use Browse Storage.', Colors.orangeAccent);
      return;
    }
    try {
      final text = await io.File(entry.path).readAsString();
      final file = IDEFile(name: entry.name, extension: entry.ext, content: text);
      file.markSaved();
      await RecentFilesService.addRecent(entry.path, entry.name, entry.ext);
      setState(() {
        _openFiles.add(file);
        _activeFileIndex = _openFiles.length - 1;
      });
      _loadActiveFileToEditor();
    } catch (e) {
      _showSnack('Could not load file: $e', Colors.redAccent);
    }
  }

  void _showCreateDialog() {
    String fileName = '';
    String selectedExt = 'py';
    _showDialogGuarded(
      context: context,
      builder: (context) =>
          StatefulBuilder(builder: (context, setStateBuilder) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1A1A24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline_rounded,
                          color: Color(0xFF9D00FF), size: 18),
                      SizedBox(width: 8),
                      Text('NEW FILE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0)),
                    ]),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _extChip('py', selectedExt, () => setStateBuilder(() => selectedExt = 'py')),
                    _extChip('cpp', selectedExt, () => setStateBuilder(() => selectedExt = 'cpp')),
                    _extChip('c', selectedExt, () => setStateBuilder(() => selectedExt = 'c')),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  autofocus: true,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'monospace'),
                  cursorColor: const Color(0xFF9D00FF),
                  decoration: InputDecoration(
                    hintText: 'Enter filename…',
                    hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontFamily: 'monospace'),
                    enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF1A1A24))),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF9D00FF))),
                  ),
                  onChanged: (val) => fileName = val,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF9D00FF).withOpacity(0.15),
                      side: const BorderSide(color: Color(0xFF9D00FF)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _createNewFile(
                          fileName.isEmpty ? 'untitled' : fileName,
                          selectedExt);
                    },
                    child: const Text('CREATE',
                        style: TextStyle(
                            color: Color(0xFF9D00FF),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _createNewFile(String name, String ext) {
    setState(() {
      final newFile = IDEFile(name: name, extension: ext);
      _openFiles.add(newFile);
      _activeFileIndex = _openFiles.length - 1;
      _lineCount = 1;
    });
    _loadActiveFileToEditor();
  }

  Future<void> _saveFile() async {
    if (!hasActiveFile) return;
    final file = _openFiles[_activeFileIndex];
    await FileService.saveFile(file.fullName, file.content);
    setState(() => file.markSaved());
    // Record in recents (path is empty on web, that's fine)
    await RecentFilesService.addRecent(file.fullName, file.name, file.extension);
    if (mounted) _showSnack('${file.fullName} saved.', const Color(0xFF00FFFF));
  }

  Future<void> _saveAs() async {
    if (!hasActiveFile) return;
    final file = _openFiles[_activeFileIndex];
    String newName = file.name;
    String newExt = file.extension;

    // First pick the directory (native shows OS folder picker; web returns null)
    final dir = await FileService.pickSaveDirectory();

    if (!mounted) return;
    _showDialogGuarded(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1A1A24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.drive_file_rename_outline_rounded,
                      color: Color(0xFF00FFFF), size: 18),
                  SizedBox(width: 8),
                  Text('SAVE AS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0)),
                ]),
                if (dir != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FFFF).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00FFFF).withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.folder_rounded, color: Color(0xFF00FFFF), size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(dir, style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _extChip('py', newExt, () => setSt(() => newExt = 'py')),
                    _extChip('cpp', newExt, () => setSt(() => newExt = 'cpp')),
                    _extChip('c', newExt, () => setSt(() => newExt = 'c')),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  autofocus: true,
                  controller: TextEditingController(text: newName),
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                  cursorColor: const Color(0xFF00FFFF),
                  decoration: InputDecoration(
                    hintText: 'New filename…',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1A1A24))),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FFFF))),
                  ),
                  onChanged: (v) => newName = v,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FFFF).withOpacity(0.15),
                      side: const BorderSide(color: Color(0xFF00FFFF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final finalName = newName.isEmpty ? file.name : newName;
                      await FileService.saveFile('$finalName.$newExt', file.content, directory: dir);
                      if (mounted) _showSnack('Saved as $finalName.$newExt', const Color(0xFF00FFFF));
                    },
                    child: const Text('SAVE AS',
                        style: TextStyle(color: Color(0xFF00FFFF), fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── Editor Actions ─────────────────────────────────────────────────────────

  Future<void> _runCode() async {
    if (!hasActiveFile) return;
    final String liveCode = _nativeController.text;
    _openFiles[_activeFileIndex].content = liveCode;

    setState(() {
      _latestOutput = "Running...";
      _terminalController.clear();
      _isTerminalOpen = true;
    });
    compilerService.runCode(
        liveCode, _openFiles[_activeFileIndex].extension);
  }

  void _stopCode() {
    if (!hasActiveFile) return;
    compilerService.stopExecution(_openFiles[_activeFileIndex].extension);
  }

  void _sendTerminalInput(String input) {
    if (!hasActiveFile) return;
    // submit() in TerminalController already echoed the line as '➜ input'.
    // We only need to forward the data to the stdin bridge.
    compilerService.sendStdin(input + '\n', _openFiles[_activeFileIndex].extension);
  }

  void _toggleTerminal() {
    setState(() {
      _isTerminalOpen = !_isTerminalOpen;
      if (_isTerminalOpen) _isLocodeAiOpen = false;
    });
  }

  void _moveCursor(int offset) {
    // Monaco handles its own keyboard navigation natively, no arrow overlay needed.
  }

  void _selectTab(int index) {
    setState(() {
      _activeFileIndex = index;
      _lineCount = _openFiles[index].content.split('\n').length;
    });
    _loadActiveFileToEditor();
  }

  void _closeTab(int index) {
    // Warn if unsaved
    if (_openFiles[index].isDirty) {
      _showUnsavedWarning(index);
      return;
    }
    _forceCloseTab(index);
  }

  void _forceCloseTab(int index) {
    setState(() {
      _openFiles.removeAt(index);
      if (_openFiles.isEmpty) {
        _activeFileIndex = -1;
      } else {
        _activeFileIndex =
            index >= _openFiles.length ? _openFiles.length - 1 : index;
        _lineCount = _openFiles[_activeFileIndex].content.split('\n').length;
      }
    });
    if (_activeFileIndex != -1) _loadActiveFileToEditor();
  }

  Future<void> _applyAiCode(String rawResponse) async {
    if (_activeFileIndex == -1) return;
    final val = _nativeController.value;
    final selection = val.selection;

    if (_nativeController.text.trim().isEmpty) {
      _nativeController.text = rawResponse;
      _showToast('Inserted code.');
    } else {
      final newText = _nativeController.text.replaceRange(
        selection.start, selection.end, rawResponse
      );
      _nativeController.text = newText;
      _nativeController.selection = TextSelection.collapsed(offset: selection.start + rawResponse.length);
      _showToast('Inserted code at cursor.');
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (_activeFileIndex == -1) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final val = _nativeController.value;
    final selection = val.selection;
    final newText = _nativeController.text.replaceRange(
      selection.start, selection.end, text
    );
    _nativeController.text = newText;
    _nativeController.selection = TextSelection.collapsed(offset: selection.start + text.length);
    _showToast('Pasted from clipboard.');
  }

  Future<void> _replaceAiCode(String rawResponse) async {
    if (_activeFileIndex == -1) return;
    _nativeController.text = rawResponse;
    _showToast('Replaced entire file.');
  }

  Future<void> _handleAiSuggestion(String rawResponse) async {
    try {
      final currentContent = _nativeController.text;

      // ── Path 1: SEARCH/REPLACE surgical mode ──────────────────────────────
      // Backend returns <<<<<<< SEARCH / ======= / >>>>>>> REPLACE blocks.
      final diffBlocks = DiffParser.parse(rawResponse);
      if (diffBlocks.isNotEmpty) {
        String patched = currentContent;
        int patchCount = 0;
        final blockDescriptions = <String>[];

        for (final block in diffBlocks) {
          final idx = patched.indexOf(block.search);
          if (idx == -1) {
            // Try trimmed matching as a fallback
            final trimmedIdx = patched.indexOf(block.search.trim());
            if (trimmedIdx == -1) {
              _showToast('Could not locate SEARCH block in file. Ask Llama to try again.');
              return;
            }
          }
          final safeIdx = patched.indexOf(block.search);
          final startLine = patched.substring(0, safeIdx).split('\n').length;
          final endLine = startLine + block.search.split('\n').length - 1;
          blockDescriptions.add('Lines $startLine–$endLine');
          patched = patched.substring(0, safeIdx) +
              block.replace +
              patched.substring(safeIdx + block.search.length);
          patchCount++;
        }

        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _LlamaReviewSheet(
            candidate: patched,
            currentContent: currentContent,
            mode: '✂ Surgical — ${patchCount} block${patchCount > 1 ? 's' : ''}: ${blockDescriptions.join(', ')}',
            diffSummary: diffBlocks.map((b) =>
              '--- ${b.search.split('\n').length} lines\n+++ ${b.replace.split('\n').length} lines').join('\n'),
            onAccept: () async {
              Navigator.of(context).pop();
              await _applyAiContentWithUndo(patched);
              // await _monacoController!.setInteractionEnabled(true);
              if (mounted && _activeFileIndex >= 0 && _activeFileIndex < _openFiles.length) {
                setState(() => _openFiles[_activeFileIndex].content = patched);
              }
              _showToast('✓ ${patchCount} patch${patchCount > 1 ? 'es' : ''} applied — Ctrl+Z to undo.');
            },
            onReject: () {
              Navigator.of(context).pop();
              _showToast('✕ Rejected.');
            },
          ),
        );
        return;
      }

      // ── Path 2: Plain code block — smart minimal range replacement ─────────
      final candidate = _extractCandidateCode(rawResponse);
      if (candidate == null || candidate.trim().isEmpty) {
        _showToast('No code found in AI response.');
        return;
      }

      final currentLines = currentContent.split('\n');
      final candidateLines = candidate.split('\n');

      // Find first differing line from top
      int topMatch = 0;
      while (topMatch < currentLines.length &&
          topMatch < candidateLines.length &&
          currentLines[topMatch] == candidateLines[topMatch]) {
        topMatch++;
      }

      // Find first differing line from bottom
      int botCur = currentLines.length - 1;
      int botCand = candidateLines.length - 1;
      while (botCur > topMatch &&
          botCand > topMatch &&
          currentLines[botCur] == candidateLines[botCand]) {
        botCur--;
        botCand--;
      }

      final String patchedContent;
      final String modeLabel;

      if (topMatch == 0 && botCur == currentLines.length - 1) {
        // Entire file is different
        patchedContent = candidate;
        modeLabel = 'Full replace';
      } else {
        // Only a slice of lines changes
        final newLines = [
          ...currentLines.sublist(0, topMatch),
          ...candidateLines.sublist(topMatch, botCand + 1),
          ...currentLines.sublist(botCur + 1),
        ];
        patchedContent = newLines.join('\n');
        modeLabel = 'Lines ${topMatch + 1}–${botCur + 1}';
      }

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LlamaReviewSheet(
          candidate: patchedContent,
          currentContent: currentContent,
          mode: modeLabel,
          diffSummary: null,
          onAccept: () async {
            Navigator.of(context).pop();
            await _applyAiContentWithUndo(patchedContent);
            // await _monacoController!.setInteractionEnabled(true);
            if (mounted && _activeFileIndex >= 0 && _activeFileIndex < _openFiles.length) {
              setState(() => _openFiles[_activeFileIndex].content = patchedContent);
            }
            _showToast('✓ Applied ($modeLabel) — Ctrl+Z to undo.');
          },
          onReject: () {
            Navigator.of(context).pop();
            _showToast('✕ Rejected.');
          },
        ),
      );
    } catch (e) {
      _showToast('Error: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}');
    }
  }

  // Keep stubs so existing state references don't break
  Future<void> _rejectPendingAiChanges() async {
    // if (_monacoController != null) await _monacoController!.clearDecorations();
    // if (_monacoController != null) await _monacoController!.setInteractionEnabled(true);
    if (!mounted) return;
    setState(() {
      _pendingAiPlan = null;
      _pendingAiCandidate = null;
      _pendingAiLineDiff = const [];
      _blockEditorInteractionForReview = false;
    });
    _showToast('Changes rejected.');
  }

  Future<void> _applyPendingAiChanges() async {
    if (_pendingAiPlan == null) return;
    final plan = _pendingAiPlan!;
    // await _monacoController!.clearDecorations();
    _nativeController.text = plan.newContent;
    // await _monacoController!.setInteractionEnabled(true);
    if (!mounted) return;
    setState(() {
      _pendingAiPlan = null;
      _pendingAiCandidate = null;
      _pendingAiLineDiff = const [];
      _blockEditorInteractionForReview = false;
    });
    if (_activeFileIndex >= 0 && _activeFileIndex < _openFiles.length) {
      _openFiles[_activeFileIndex].content = plan.newContent;
    }
    _showToast('✓ Changes accepted.');
  }

  Future<void> _applyAiContentWithUndo(String newContent) async {
    _nativeController.text = newContent;
  }

  String? _extractCandidateCode(String rawResponse) {
    final blockRegex = RegExp(r'```(?:\w+)?\n([\s\S]*?)```');
    final matches = blockRegex.allMatches(rawResponse).toList();
    if (matches.isNotEmpty) {
      final joined = matches
          .map((m) => (m.group(1) ?? '').trimRight())
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      if (joined.trim().isNotEmpty) return joined;
    }

    // Fallback: accept plain-text model output as code.
    var text = rawResponse.trim();
    text = text.replaceAll(RegExp("^Here(?: is|'s).*?:\\s*", caseSensitive: false), '');
    if (text.startsWith('```')) {
      final endFence = text.lastIndexOf('```');
      if (endFence > 0) {
        text = text.substring(0, endFence).trimRight();
      }
      // drop the opening fence line (```lang or just ```)
      final firstNewline = text.indexOf('\n');
      if (firstNewline != -1) {
        text = text.substring(firstNewline + 1);
      } else {
        // one-line fenced output like: ```python print("hi") ```
        text = text.replaceFirst(RegExp(r'^```[a-zA-Z0-9_+-]*\s*'), '');
      }
    }
    text = text.replaceAll('```', '').trim();
    return text.isEmpty ? null : text;
  }



  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showUnsavedWarning(int index) {
    _showDialogGuarded(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF333344)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFFAA00), size: 32),
              const SizedBox(height: 16),
              Text(
                '${_openFiles[index].fullName} has unsaved changes.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF333344))),
                    onPressed: () {
                      Navigator.pop(context);
                      _forceCloseTab(index);
                    },
                    child: const Text('Discard',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF00FFFF).withOpacity(0.15),
                      side: const BorderSide(color: Color(0xFF00FFFF)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      FileService.saveFile(_openFiles[index].fullName,
                          _openFiles[index].content);
                      setState(() => _openFiles[index].markSaved());
                      _forceCloseTab(index);
                    },
                    child: const Text('Save & Close',
                        style: TextStyle(
                            color: Color(0xFF00FFFF),
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: const Color(0xFF0F0F16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color, width: 1),
      ),
      content: Row(children: [
        Icon(Icons.check_circle_rounded, color: color, size: 16),
        const SizedBox(width: 10),
        Flexible(child: Text(msg,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _fileMenuAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  Widget _extChip(String ext, String selected, VoidCallback onTap) {
    bool isSel = ext == selected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSel
              ? const Color(0xFF00FFFF).withOpacity(0.15)
              : Colors.transparent,
          border: Border.all(
              color:
                  isSel ? const Color(0xFF00FFFF) : const Color(0xFF1A1A24)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('.$ext',
            style: TextStyle(
                color: isSel ? const Color(0xFF00FFFF) : Colors.white54,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  void _toggleLocodeAi() {
    setState(() {
      _isLocodeAiOpen = !_isLocodeAiOpen;
      if (_isLocodeAiOpen) _isTerminalOpen = false;
    });

    // Critical: if user opens Locode AI with no file open, Monaco isn't mounted.
    // Create a file immediately so Llama suggestions can be reviewed/applied.
    if (_isLocodeAiOpen) {
      _ensureActiveFileForAi();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgPureBlack = _isDarkMode ? const Color(0xFF000000) : const Color(0xFFF8FAFC);
    final Color borderNeon = _isDarkMode ? const Color(0xFF1A1A24) : const Color(0xFFE2E8F0);
    final Color textPrimary = _isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final Color textMuted = _isDarkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    final Color cyanAccent = _isDarkMode ? const Color(0xFF00FFFF) : const Color(0xFF0EA5E9);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: bgPureBlack,
      body: SafeArea(
        child: Column(
          children: [
            EditorHeader(
              onMenuTap: _showFileMenu,
              onSaveFile: _saveFile,
              onSaveAs: _saveAs,
              onRun: _runCode,
              onStop: _stopCode,
              onToggleDarkMode: () async {
                final newValue = !_isDarkMode;
                setState(() => _isDarkMode = newValue);
                await SettingsService.setDarkMode(newValue);
              },
              isRunning: _isRunning,
              isDarkMode: _isDarkMode,
              hasActiveFile: hasActiveFile,
              activeExtension: hasActiveFile ? _openFiles[_activeFileIndex].extension : '',
              isPythonOnline: _isPythonOnline,
              onTogglePythonEngine: () {
                setState(() {
                  _isPythonOnline = !_isPythonOnline;
                  compilerService.setPythonOnline(_isPythonOnline);
                });
              },
            ),

            EditorTabBar(
              files: _openFiles,
              currentIndex: _activeFileIndex,
              onTabSelected: _selectTab,
              onTabClosed: _closeTab,
              isDarkMode: _isDarkMode,
            ),

            // ── Inline Run / Debug Toolbar ──────────────────────────────────
            if (hasActiveFile)
              Container(
                decoration: BoxDecoration(
                  color: bgPureBlack,
                  border: Border(bottom: BorderSide(color: borderNeon, width: 1)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 4),
                      // Undo / Redo
                      IconButton(icon: const Icon(Icons.undo_rounded, size: 20), onPressed: () {
                        _nativeController.undo();
                      }, tooltip: 'Undo', splashRadius: 20, color: textPrimary),
                      IconButton(icon: const Icon(Icons.redo_rounded, size: 20), onPressed: () {
                        _nativeController.redo();
                      }, tooltip: 'Redo', splashRadius: 20, color: textPrimary),
                      const SizedBox(width: 4),
                      Container(width: 1, height: 20, color: const Color(0xFF1A1A24)),
                      const SizedBox(width: 4),
                      // Navigation
                      IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: () {
                        final val = _nativeController.value;
                        if (val.selection.start > 0) {
                          _nativeController.selection = TextSelection.collapsed(offset: val.selection.start - 1);
                        }
                      }, tooltip: 'Left', splashRadius: 20, color: textPrimary),
                      IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18), onPressed: () {
                        final val = _nativeController.value;
                        if (val.selection.end < _nativeController.text.length) {
                          _nativeController.selection = TextSelection.collapsed(offset: val.selection.end + 1);
                        }
                      }, tooltip: 'Right', splashRadius: 20, color: textPrimary),
                      const SizedBox(width: 4),
                      Container(width: 1, height: 20, color: const Color(0xFF1A1A24)),
                      const SizedBox(width: 4),
                      // Select All / Copy / Paste
                      IconButton(icon: const Icon(Icons.select_all_rounded, size: 20), onPressed: () {
                        _nativeController.selection = TextSelection(baseOffset: 0, extentOffset: _nativeController.text.length);
                      }, tooltip: 'Select All', splashRadius: 20, color: const Color(0xFF00FFFF)),
                      IconButton(icon: const Icon(Icons.content_copy_rounded, size: 20), onPressed: () {
                        Clipboard.setData(ClipboardData(text: _nativeController.selection.textInside(_nativeController.text)));
                      }, tooltip: 'Copy', splashRadius: 20, color: textPrimary),
                      IconButton(icon: const Icon(Icons.content_paste_rounded, size: 20), onPressed: _pasteFromClipboard, tooltip: 'Paste', splashRadius: 20, color: textPrimary),
                    ],
                  ),
                ),
              ),

            // ── Editor Area ─────────────────────────────────────────────────
            // ── Llama 3 Accept / Reject Review Bar ─────────────────────────
            if (_pendingAiPlan != null && _pendingAiCandidate != null)
              _AiReviewBar(
                mode: _pendingAiPlan!.mode,
                candidateCode: _pendingAiCandidate!,
                removedLines: _pendingAiLineDiff
                    .where((d) => d.kind == _DiffKind.remove)
                    .map((d) => d.text)
                    .take(80)
                    .toList(),
                addedLines: _pendingAiLineDiff
                    .where((d) => d.kind == _DiffKind.add)
                    .map((d) => d.text)
                    .take(80)
                    .toList(),
                onApply: _applyPendingAiChanges,
                onReject: _rejectPendingAiChanges,
              ),

            Expanded(
              child: Container(
                color: bgPureBlack,
                child: !hasActiveFile
                    ? _buildEmptyState()
                    : Stack(children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (_isTerminalOpen || _isLocodeAiOpen) {
                                setState(() {
                                  _isTerminalOpen = false;
                                  _isLocodeAiOpen = false;
                                });
                              }
                            },
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                              Container(
                                width: 45,
                                padding: const EdgeInsets.only(top: 11, bottom: 8),
                                decoration: BoxDecoration(
                                  color: bgPureBlack,
                                  border: Border(right: BorderSide(color: borderNeon, width: 1)),
                                ),
                                child: ListView.builder(
                                  controller: _gutterScrollController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemCount: _lineCount,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      height: 21.0,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
                                  child: TextField(
                                    scrollController: _editorScrollController,
                                    controller: _nativeController,
                                    focusNode: _editorFocusNode,
                              maxLines: null,
                              expands: true,
                              cursorColor: const Color(0xFF00FF88),
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 15,
                                color: Color(0xFFABB2BF),
                                height: 1.4,
                              ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onTap: () {
                                  if (_isTerminalOpen || _isLocodeAiOpen) {
                                    setState(() {
                                      _isTerminalOpen = false;
                                      _isLocodeAiOpen = false;
                                    });
                                  }
                                },
                                // Native Android handles work automatically here!
                              ),
                            ),
                          ),
                              ],
                            ),
                          ),
                        ),
                        // Align the overlay panels to the bottom of the editor stack
                        // The Scaffold already resizes for the keyboard, so we just stick to the bottom.
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TerminalPanel(
                                  isOpen: _isTerminalOpen,
                                  controller: _terminalController,
                                  isDarkMode: _isDarkMode,
                                  isRunning: _isRunning,
                                  onInput: _sendTerminalInput,
                                  onStop: _stopCode,
                                  onClear: () {
                                    _terminalController.clear();
                                  },
                                  onToggle: _toggleTerminal),
                              LocodeAiPanel(
                                isOpen: _isLocodeAiOpen,
                                isDarkMode: _isDarkMode,
                                onClose: _toggleLocodeAi,
                                activeFileName: hasActiveFile ? _openFiles[_activeFileIndex].fullName : "",
                                getFileContent: () async => _nativeController.text,
                                onApplyCode: _applyAiCode,
                                onReplaceFile: _replaceAiCode,
                                onAiSuggestion: _handleAiSuggestion,
                              ),
                            ],
                          ),
                        ),
                      ]),
              ),
            ),

            EditorStatusBar(
                latestOutput: _latestOutput,
                isDarkMode: _isDarkMode,
                activeExtension: hasActiveFile
                    ? _openFiles[_activeFileIndex].extension
                    : ''),

            EditorDock(
              onToggleTerminal: _toggleTerminal,
              onToggleLocodeAi: _toggleLocodeAi,
              isTerminalOpen: _isTerminalOpen,
              isLocodeAiOpen: _isLocodeAiOpen,
              isDarkMode: _isDarkMode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    const cyan = Color(0xFF00FFFF);
    const purple = Color(0xFF9D00FF);
    const textMuted = Color(0xFF475569);
    const borderNeon = Color(0xFF1A1A24);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent files section
          if (_recentFiles.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.history_rounded, color: cyan, size: 15),
              const SizedBox(width: 8),
              const Text('RECENT FILES',
                  style: TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w800, letterSpacing: 2.0)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await RecentFilesService.clearRecent();
                  setState(() { _recentFiles.clear(); _selectedRecent.clear(); });
                },
                child: Text('Clear all',
                    style: TextStyle(color: textMuted.withOpacity(0.5), fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 12),
            ..._recentFiles.asMap().entries.map((e) {
              final i = e.key; final entry = e.value;
              final isSel = _selectedRecent.contains(i);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSel) _selectedRecent.remove(i);
                  else _selectedRecent.add(i);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSel ? cyan.withOpacity(0.06) : const Color(0xFF05050A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSel ? cyan.withOpacity(0.5) : borderNeon),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _extColor(entry.ext).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _extColor(entry.ext).withOpacity(0.4)),
                      ),
                      child: Text('.${entry.ext}',
                          style: TextStyle(color: _extColor(entry.ext),
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.fullName,
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        if (entry.path.isNotEmpty)
                          Text(entry.path,
                              style: TextStyle(color: textMuted.withOpacity(0.4),
                                  fontSize: 9, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis),
                      ],
                    )),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSel ? cyan : Colors.transparent,
                        border: Border.all(color: isSel ? cyan : borderNeon, width: 1.5),
                      ),
                      child: isSel
                          ? const Icon(Icons.check_rounded, color: Colors.black, size: 13)
                          : null,
                    ),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 8),
            // Open selected button
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedRecent.isNotEmpty
                  ? SizedBox(
                      key: const ValueKey('open'),
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.launch_rounded, color: Colors.black, size: 16),
                        label: Text(
                          'Open ${_selectedRecent.length} file${_selectedRecent.length > 1 ? 's' : ''}',
                          style: const TextStyle(color: Colors.black,
                              fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cyan,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _openRecentFromDashboard,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
            const SizedBox(height: 28),
            Divider(color: borderNeon.withOpacity(0.5)),
            const SizedBox(height: 28),
          ],

          // Empty state CTA
          Center(
            child: Column(children: [
              Icon(Icons.terminal_rounded,
                  size: 52, color: textMuted.withOpacity(0.25)),
              const SizedBox(height: 20),
              Text('SYSTEM STANDBY',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                      letterSpacing: 4.0, color: textMuted.withOpacity(0.4))),
              const SizedBox(height: 8),
              Text('Tap ☰ to open or create a file',
                  style: TextStyle(fontSize: 12, color: textMuted.withOpacity(0.4))),
            ]),
          ),
        ],
      ),
    );
  }

  Color _extColor(String ext) {
    switch (ext) {
      case 'py': return const Color(0xFF3B82F6);
      case 'cpp': return const Color(0xFF9D00FF);
      case 'js': return const Color(0xFFFBBF24);
      default: return const Color(0xFF00FFFF);
    }
  }

  Future<void> _openRecentFromDashboard() async {
    for (final i in _selectedRecent) {
      final entry = _recentFiles[i];
      try {
        final result = await FileService.openFile();
        if (result != null) {
          final file = IDEFile(
              name: result.name,
              extension: result.ext,
              content: result.content);
          file.markSaved();
          setState(() {
            _openFiles.add(file);
            _activeFileIndex = _openFiles.length - 1;
          });
          _loadActiveFileToEditor();
        }
      } catch (_) {}
    }
    setState(() => _selectedRecent.clear());
  }
}

/// Tracks a single live diff block - the original search lines (shown red)
/// and the inserted replacement lines (shown green) in Monaco.
class _AiEditPlan {
  final String mode;
  final String newContent;

  const _AiEditPlan({
    required this.mode,
    required this.newContent,
  });
}

class _IndexedEdit {
  final int start;
  final int end;
  final String replacement;

  const _IndexedEdit({
    required this.start,
    required this.end,
    required this.replacement,
  });
}

enum _DiffKind { add, remove }

// ── Llama 3 Review Sheet ───────────────────────────────────────────────────────
/// Modal bottom sheet shown when user taps "Apply to File".
/// Uses showModalBottomSheet so it's always on top of everything.
class _LlamaReviewSheet extends StatelessWidget {
  final String candidate;
  final String currentContent;
  final String mode;          // e.g. 'Surgical — 1 block: Lines 5–7'
  final String? diffSummary;  // optional SEARCH/REPLACE block summary
  final Future<void> Function() onAccept;
  final VoidCallback onReject;

  const _LlamaReviewSheet({
    required this.candidate,
    required this.currentContent,
    required this.mode,
    required this.diffSummary,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final addedLines = candidate.split('\n').length;
    final removedLines = currentContent.split('\n').length;
    final isSurgical = mode.startsWith('✂');

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSurgical
              ? const Color(0xFF007AFF66)
              : const Color(0xFF00FF8855),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isSurgical ? const Color(0xFF007AFF) : const Color(0xFF00FF88)).withOpacity(0.15),
            blurRadius: 30, spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isSurgical ? const Color(0xFF007AFF) : const Color(0xFF00FF88)).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (isSurgical ? const Color(0xFF007AFF) : const Color(0xFF00FF88)).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSurgical ? Icons.content_cut_rounded : Icons.auto_awesome_rounded,
                        size: 11,
                        color: isSurgical ? const Color(0xFF007AFF) : const Color(0xFF00FF88),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isSurgical ? 'SURGICAL' : 'LLAMA 3',
                        style: TextStyle(
                          color: isSurgical ? const Color(0xFF007AFF) : const Color(0xFF00FF88),
                          fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(mode,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '+$addedLines  -$removedLines lines',
                  style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Diff summary (for surgical mode) ─────────────────────────────
          if (diffSummary != null) ...
            [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF007AFF).withOpacity(0.25)),
                ),
                child: Text(
                  diffSummary!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white54, height: 1.5),
                ),
              ),
              const SizedBox(height: 10),
            ],

          // ── Code preview ─────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E2030)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Text(
                candidate,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Color(0xFFD4D4D4), height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Accept / Reject buttons ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              children: [
                // ✕ Reject
                Expanded(
                  child: GestureDetector(
                    onTap: onReject,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.7), width: 1.5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close_rounded, color: Color(0xFFFF5555), size: 20),
                          SizedBox(width: 8),
                          Text('Reject', style: TextStyle(color: Color(0xFFFF5555), fontWeight: FontWeight.w800, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // ✓ Accept
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => onAccept(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSurgical
                              ? [const Color(0xFF0055CC), const Color(0xFF007AFF)]
                              : [const Color(0xFF00AA44), const Color(0xFF00FF88)],
                          begin: Alignment.centerLeft, end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (isSurgical ? const Color(0xFF007AFF) : const Color(0xFF00FF88)).withOpacity(0.4),
                            blurRadius: 18, offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            isSurgical ? 'Apply Surgical Patch' : 'Accept & Apply',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineDiff {
  final _DiffKind kind;
  final String text;
  final int? oldLine;

  const _LineDiff({
    required this.kind,
    required this.text,
    required this.oldLine,
  });
}

class _AiDiffPreviewBody extends StatelessWidget {
  final String mode;
  final String candidateCode;
  final List<String> removedLines;
  final List<String> addedLines;

  const _AiDiffPreviewBody({
    required this.mode,
    required this.candidateCode,
    required this.removedLines,
    required this.addedLines,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode: $mode',
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text('Proposed Code', style: TextStyle(color: Color(0xFF8AB4F8), fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0x1A8AB4F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x668AB4F8)),
          ),
          child: Text(
            candidateCode,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        if (removedLines.isNotEmpty) ...[
          const Text('Removals', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x33FF0000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x66FF6B6B)),
            ),
            child: Text(
              removedLines.map((l) => '- $l').join('\n'),
              style: const TextStyle(color: Color(0xFFFFB3B3), fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (addedLines.isNotEmpty) ...[
          const Text('Additions', style: TextStyle(color: Color(0xFF50FA7B), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x3300FF00),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x6650FA7B)),
            ),
            child: Text(
              addedLines.map((l) => '+ $l').join('\n'),
              style: const TextStyle(color: Color(0xFFB8FFCC), fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }
}

class _AiReviewBar extends StatefulWidget {
  final String mode;
  final String candidateCode;
  final List<String> removedLines;
  final List<String> addedLines;
  final Future<void> Function() onApply;
  final Future<void> Function() onReject;

  const _AiReviewBar({
    required this.mode,
    required this.candidateCode,
    required this.removedLines,
    required this.addedLines,
    required this.onApply,
    required this.onReject,
  });

  @override
  State<_AiReviewBar> createState() => _AiReviewBarState();
}

class _AiReviewBarState extends State<_AiReviewBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00FF8866), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00FF88).withOpacity(0.10),
              blurRadius: 20,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title row ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF88).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: Color(0xFF00FF88), size: 11),
                        SizedBox(width: 5),
                        Text('LLAMA 3', style: TextStyle(
                          color: Color(0xFF00FF88), fontSize: 10,
                          fontWeight: FontWeight.w900, letterSpacing: 1.2,
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI suggestion ready — ${widget.mode}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        _expanded ? '▲ hide' : '▼ preview',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Big Accept / Reject Buttons ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  // ── REJECT ──────────────────────────────────────────────
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onReject,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: const Color(0xFFFF3B30).withOpacity(0.65), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withOpacity(0.15),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, color: Color(0xFFFF5555), size: 18),
                            SizedBox(width: 8),
                            Text('Reject',
                                style: TextStyle(
                                  color: Color(0xFFFF5555),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ── ACCEPT ──────────────────────────────────────────────
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onApply,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00AA44), Color(0xFF00FF88)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00FF88).withOpacity(0.40),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, color: Colors.black, size: 18),
                            SizedBox(width: 8),
                            Text('Accept',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_expanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Color(0xFF1A1A24)),
                    const SizedBox(height: 8),
                    const Text('Proposed Code', style: TextStyle(color: Color(0xFF8AB4F8), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1A8AB4F8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x668AB4F8)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.candidateCode,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.removedLines.isNotEmpty) ...[
                      const Text('Removals', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x22FF0000),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x66FF6B6B)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            widget.removedLines.map((l) => '- $l').join('\n'),
                            style: const TextStyle(color: Color(0xFFFFB3B3), fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (widget.addedLines.isNotEmpty) ...[
                      const Text('Additions', style: TextStyle(color: Color(0xFF50FA7B), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x2200FF00),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x6650FA7B)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            widget.addedLines.map((l) => '+ $l').join('\n'),
                            style: const TextStyle(color: Color(0xFFB8FFCC), fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
