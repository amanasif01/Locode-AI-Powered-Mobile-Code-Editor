import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/compiler_service_mobile.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'widgets/interactive_diff_editor.dart';
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
import 'dart:io' as io;
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

  _AiEditPlan? _pendingAiPlan;
  String? _pendingAiCandidate;
  List<_LineDiff> _pendingAiLineDiff = const [];
  bool _isDiffReviewing = false;
  String? _suggestionCandidate = null;

  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();
  int _lineCount = 1;

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
        'comment': const TextStyle(color: Color(0xFF5C6370), fontStyle: FontStyle.italic),
        'string': const TextStyle(color: Color(0xFF98C379)),
        'keyword': const TextStyle(color: Color(0xFFC678DD), fontWeight: FontWeight.bold),
        'type': const TextStyle(color: Color(0xFFE5C07B)),
        'function': const TextStyle(color: Color(0xFF61AFEF)),
        'number': const TextStyle(color: Color(0xFFD19A66)),
        'bracket': const TextStyle(color: Color(0xFF56B6C2), fontWeight: FontWeight.bold),
        'operator': const TextStyle(color: Color(0xFFABB2BF)),
        'variable': const TextStyle(color: Color(0xFFE06C75)),
      },
    );
    _nativeController.addListener(() { _onContentChanged(_nativeController.text); });
    compilerService.init();
    compilerService.setTerminalController(_terminalController);
    compilerService.outputStream.listen((msg) {
      if (mounted) {
        setState(() => _latestOutput = msg);
        _terminalController.addOutput(msg);
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
    if (mounted) {
      setState(() => _recentFiles = recent);
      if (_openFiles.isEmpty && recent.isNotEmpty) { _openSingleRecent(recent.first); }
    }
  }

  void _onContentChanged(String newContent) {
    if (hasActiveFile) {
      final file = _openFiles[_activeFileIndex];
      file.content = newContent;
      final newCount = newContent.split('\n').length;
      if (newCount != _lineCount) setState(() => _lineCount = newCount < 1 ? 1 : newCount);
    }
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
    });
  }

  @override
  void dispose() {
    _editorScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  void _toggleLocodeAi() {
    setState(() {
      _isLocodeAiOpen = !_isLocodeAiOpen;
      if (_isLocodeAiOpen) _isTerminalOpen = false;
    });
    if (_isLocodeAiOpen && !hasActiveFile) {
      _createNewFile('llama_suggestion', 'txt');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgPureBlack = _isDarkMode ? const Color(0xFF000000) : const Color(0xFFF8FAFC);
    final Color borderNeon = _isDarkMode ? const Color(0xFF1A1A24) : const Color(0xFFE2E8F0);
    final Color textPrimary = _isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);

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
                final nv = !_isDarkMode;
                setState(() => _isDarkMode = nv);
                await SettingsService.setDarkMode(nv);
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
            if (hasActiveFile)
              Container(
                decoration: BoxDecoration(color: bgPureBlack, border: Border(bottom: BorderSide(color: borderNeon, width: 1))),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.undo_rounded, size: 20), onPressed: () => _nativeController.undo(), color: textPrimary),
                      IconButton(icon: const Icon(Icons.redo_rounded, size: 20), onPressed: () => _nativeController.redo(), color: textPrimary),
                      Container(width: 1, height: 20, color: borderNeon, margin: const EdgeInsets.symmetric(horizontal: 8)),
                      IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: () {
                        final val = _nativeController.value;
                        if (val.selection.start > 0) _nativeController.selection = TextSelection.collapsed(offset: val.selection.start - 1);
                      }, color: textPrimary),
                      IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18), onPressed: () {
                        final val = _nativeController.value;
                        if (val.selection.end < _nativeController.text.length) _nativeController.selection = TextSelection.collapsed(offset: val.selection.end + 1);
                      }, color: textPrimary),
                      Container(width: 1, height: 20, color: borderNeon, margin: const EdgeInsets.symmetric(horizontal: 8)),
                      IconButton(icon: const Icon(Icons.select_all_rounded, size: 20), onPressed: () => _nativeController.selection = TextSelection(baseOffset: 0, extentOffset: _nativeController.text.length), color: const Color(0xFF00FFFF)),
                      IconButton(icon: const Icon(Icons.content_copy_rounded, size: 20), onPressed: () => Clipboard.setData(ClipboardData(text: _nativeController.selection.textInside(_nativeController.text))), color: textPrimary),
                      IconButton(icon: const Icon(Icons.content_paste_rounded, size: 20), onPressed: _pasteFromClipboard, color: textPrimary),
                    ],
                  ),
                ),
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
                                  padding: const EdgeInsets.only(top: 11),
                                  decoration: BoxDecoration(color: bgPureBlack, border: Border(right: BorderSide(color: borderNeon, width: 1))),
                                  child: ListView.builder(
                                    controller: _gutterScrollController,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _lineCount,
                                    itemBuilder: (ctx, i) => Container(
                                      height: 21,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text('${i + 1}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF475569))),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: TextField(
                                      scrollController: _editorScrollController,
                                      controller: _nativeController,
                                      focusNode: _editorFocusNode,
                                      maxLines: null,
                                      expands: true,
                                      cursorColor: const Color(0xFF00FF88),
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: Color(0xFFABB2BF), height: 1.4),
                                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                      onTap: () {
                                        if (_isTerminalOpen || _isLocodeAiOpen) {
                                          setState(() {
                                            _isTerminalOpen = false;
                                            _isLocodeAiOpen = false;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isDiffReviewing && _suggestionCandidate != null)
                          Positioned.fill(
                            child: InteractiveDiffEditor(
                              originalCode: _nativeController.text,
                              newCode: _suggestionCandidate!,
                              isDarkMode: _isDarkMode,
                              onApply: (c) { setState(() { _nativeController.text = c; _isDiffReviewing = false; _suggestionCandidate = null; if (hasActiveFile) _openFiles[_activeFileIndex].content = c; }); },
                              onCancel: () { setState(() { _isDiffReviewing = false; _suggestionCandidate = null; }); },
                            ),
                          ),
                        if (_isLocodeAiOpen)
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: LocodeAiPanel(
                              isOpen: _isLocodeAiOpen,
                              isDarkMode: _isDarkMode,
                              onClose: _toggleLocodeAi,
                              activeFileName: hasActiveFile ? _openFiles[_activeFileIndex].fullName : '',
                              getFileContent: () async => _nativeController.text,
                              onApplyCode: _applyAiCode,
                              onReplaceFile: _replaceAiCode,
                              onAiSuggestion: _enterDiffReview,
                            ),
                          ),
                      ]),
              ),
            ),
            TerminalPanel(
              isOpen: _isTerminalOpen,
              controller: _terminalController,
              isDarkMode: _isDarkMode,
              isRunning: _isRunning,
              onInput: _sendTerminalInput,
              onStop: _stopCode,
              onClear: () { _terminalController.clear(); },
              onToggle: _toggleTerminal,
            ),
            EditorStatusBar(latestOutput: _latestOutput, isDarkMode: _isDarkMode, activeExtension: hasActiveFile ? _openFiles[_activeFileIndex].extension : ''),
            EditorDock(onToggleTerminal: _toggleTerminal, onToggleLocodeAi: _toggleLocodeAi, isTerminalOpen: _isTerminalOpen, isLocodeAiOpen: _isLocodeAiOpen, isDarkMode: _isDarkMode),
            Offstage(offstage: true, child: SizedBox(width: 1, height: 1, child: WebViewWidget(controller: compilerService.webViewController))),
          ],
        ),
      ),
    );
  }

  void _applyAiCode(String code) { setState(() { _nativeController.text = code; if (hasActiveFile) _openFiles[_activeFileIndex].content = code; }); }
  void _replaceAiCode(String code) { _applyAiCode(code); }
  void _enterDiffReview(String suggestion) { setState(() { _suggestionCandidate = suggestion; _isDiffReviewing = true; }); }
  void _pasteFromClipboard() async { final data = await Clipboard.getData('text/plain'); if (data?.text != null) { _nativeController.text = _nativeController.text + data!.text!; } }

  void _showFileMenu() {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: const Color(0xFF0A0A12), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1A1A24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('LOCODE MENU', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _menuAction(Icons.sd_storage_rounded, 'Browse', const Color(0xFF00FFFF), () { Navigator.pop(context); _openFile(); })),
            const SizedBox(width: 12),
            Expanded(child: _menuAction(Icons.add_circle_outline_rounded, 'New File', const Color(0xFF9D00FF), () { Navigator.pop(context); _showCreateDialog(); })),
          ]),
        ]),
      ),
    ));
  }

  Widget _menuAction(IconData i, String l, Color c, VoidCallback t) => GestureDetector(
    onTap: t,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.3))),
      child: Column(children: [Icon(i, color: c, size: 24), const SizedBox(height: 8), Text(l, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold))]),
    ),
  );

  Future<void> _openFile() async {
    final result = await FileService.openFile();
    if (result == null) return;
    final file = IDEFile(name: result.name, extension: result.ext, content: result.content, absolutePath: result.path);
    file.markSaved();
    await RecentFilesService.addRecent(result.path, result.name, result.ext);
    setState(() { _openFiles.add(file); _activeFileIndex = _openFiles.length - 1; });
    _loadActiveFileToEditor();
  }

  void _showCreateDialog() {
    String name = ''; String ext = 'py';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF0A0A12), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1A1A24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('NEW FILE', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
          const SizedBox(height: 20),
          TextField(autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Filename...', hintStyle: TextStyle(color: Colors.white24)), onChanged: (v) => name = v),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _createNewFile(name.isEmpty ? 'untitled' : name, ext); }, child: const Text('CREATE')),
        ]),
      ),
    )));
  }

  void _createNewFile(String name, String ext) {
    setState(() { final f = IDEFile(name: name, extension: ext); _openFiles.add(f); _activeFileIndex = _openFiles.length - 1; });
    _loadActiveFileToEditor();
  }

  Future<void> _saveFile() async {
    if (!hasActiveFile) return;
    final f = _openFiles[_activeFileIndex]; f.content = _nativeController.text;
    if (f.absolutePath == null) { await _saveAs(); return; }
    await FileService.saveFile(f.absolutePath!, f.content);
    setState(() => f.markSaved());
    _showSnack('Saved ${f.fullName}', const Color(0xFF00FFFF));
  }

  Future<void> _saveAs() async {
    if (!hasActiveFile) return;
    final f = _openFiles[_activeFileIndex];
    final dir = await FileService.pickSaveDirectory();
    if (dir == null) return;
    final path = dir.endsWith('/') ? '$dir${f.fullName}' : '$dir/${f.fullName}';
    await FileService.saveFile(path, _nativeController.text);
    setState(() { f.absolutePath = path; f.markSaved(); });
    _showSnack('Saved to $path', const Color(0xFF00FFFF));
  }

  Future<void> _runCode() async {
    if (!hasActiveFile) return;
    setState(() { _isTerminalOpen = true; _terminalController.clear(); });
    compilerService.runCode(_nativeController.text, _openFiles[_activeFileIndex].extension);
  }

  void _stopCode() { if (hasActiveFile) compilerService.stopExecution(_openFiles[_activeFileIndex].extension); }
  void _sendTerminalInput(String i) { if (hasActiveFile) compilerService.sendStdin(i + '\n', _openFiles[_activeFileIndex].extension); }
  void _toggleTerminal() { setState(() { _isTerminalOpen = !_isTerminalOpen; if (_isTerminalOpen) _isLocodeAiOpen = false; }); }
  void _selectTab(int i) { setState(() { _activeFileIndex = i; }); _loadActiveFileToEditor(); }
  void _closeTab(int i) { setState(() { _openFiles.removeAt(i); if (_openFiles.isEmpty) _activeFileIndex = -1; else if (_activeFileIndex >= _openFiles.length) _activeFileIndex = _openFiles.length - 1; }); _loadActiveFileToEditor(); }
  void _showSnack(String m, Color c) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c.withOpacity(0.8))); }
  void _showToast(String m) { _showSnack(m, const Color(0xFF00FFFF)); }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.code_rounded, size: 64, color: Color(0xFF1A1A24)),
    const SizedBox(height: 16),
    const Text('Welcome to Locode', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Open or create a file to start coding', style: TextStyle(color: Colors.white54)),
    const SizedBox(height: 24),
    ElevatedButton(onPressed: _showFileMenu, child: const Text('GET STARTED')),
  ]));

  Future<void> _openSingleRecent(RecentFileEntry e) async {
    try {
      final f = io.File(e.path);
      if (await f.exists()) {
        final c = await f.readAsString();
        final ideF = IDEFile(name: e.name, extension: e.ext, content: c, absolutePath: e.path);
        setState(() { _openFiles.add(ideF); _activeFileIndex = _openFiles.length - 1; });
        _loadActiveFileToEditor();
      }
    } catch (_) {}
  }
}

class _AiEditPlan { final String mode; _AiEditPlan({required this.mode}); }
class _LineDiff { final String text; final _DiffKind kind; _LineDiff(this.text, this.kind); }
enum _DiffKind { add, remove, same }

class _AiReviewBar extends StatelessWidget {
  final String mode; final String candidateCode; final List<String> removedLines; final List<String> addedLines;
  final VoidCallback onApply; final VoidCallback onReject;
  const _AiReviewBar({required this.mode, required this.candidateCode, required this.removedLines, required this.addedLines, required this.onApply, required this.onReject});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1A1A24),
      child: Row(children: [
        const Icon(Icons.auto_awesome, color: Color(0xFF00FFFF), size: 16),
        const SizedBox(width: 8),
        const Expanded(child: Text('AI Suggestion Ready', style: TextStyle(color: Colors.white, fontSize: 12))),
        TextButton(onPressed: onReject, child: const Text('REJECT', style: TextStyle(color: Colors.redAccent))),
        ElevatedButton(onPressed: onApply, child: const Text('APPLY')),
      ]),
    );
  }
}
void _applyPendingAiChanges() {}
void _rejectPendingAiChanges() {}
