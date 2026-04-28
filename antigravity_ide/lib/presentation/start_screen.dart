import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../domain/recent_files_service.dart';
import '../domain/ide_file.dart';

/// Startup screen shown every launch.
/// Displays up to 5 recent files (Android: only if they still exist on disk).
/// User can multi-select and open them all at once.
class StartScreen extends StatefulWidget {
  /// Called when the user is done selecting files. Passes the files to open.
  final void Function(List<IDEFile> filesToOpen) onComplete;

  const StartScreen({super.key, required this.onComplete});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  List<RecentFileEntry> _recent = [];
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final entries = await RecentFilesService.loadRecent();
    if (mounted) setState(() => _recent = entries);
  }

  Future<void> _openSelected() async {
    final filesToOpen = <IDEFile>[];
    for (final i in _selected) {
      final entry = _recent[i];
      try {
        String content = '';
        if (!kIsWeb && entry.path.isNotEmpty) {
          content = await File(entry.path).readAsString();
        }
        final file = IDEFile(name: entry.name, extension: entry.ext, content: content);
        file.markSaved();
        filesToOpen.add(file);
      } catch (_) {
        // File might have been deleted between check and open — silently skip
      }
    }
    widget.onComplete(filesToOpen);
  }

  @override
  Widget build(BuildContext context) {
    const bgBlack = Color(0xFF000000);
    const borderNeon = Color(0xFF1A1A24);
    const cyan = Color(0xFF00FFFF);
    const purple = Color(0xFF9D00FF);
    const textMuted = Color(0xFF475569);

    return Scaffold(
      backgroundColor: bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: borderNeon)),
              ),
              child: Row(
                children: [
                  // Logo
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [cyan, purple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(b),
                    child: const Stack(alignment: Alignment.center, children: [
                      Icon(Icons.hexagon_outlined, color: Colors.white, size: 32),
                      Icon(Icons.circle, color: Colors.white, size: 9),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Colors.white, cyan],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ).createShader(b),
                    child: const Text('LOCODE',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4.0,
                            color: Colors.white)),
                  ),
                  const Spacer(),
                  Text('v1.0', style: TextStyle(color: textMuted.withOpacity(0.5), fontSize: 12)),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Recent files section
                          if (_recent.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.history_rounded, color: Color(0xFF00FFFF), size: 16),
                                const SizedBox(width: 8),
                                const Text('RECENT FILES',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.0)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () async {
                                    await RecentFilesService.clearRecent();
                                    setState(() => _recent.clear());
                                  },
                                  child: Text('Clear',
                                      style: TextStyle(
                                          color: textMuted.withOpacity(0.5),
                                          fontSize: 11)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(_recent.length, (i) {
                              final entry = _recent[i];
                              final isSelected = _selected.contains(i);
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) _selected.remove(i);
                                    else _selected.add(i);
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? cyan.withOpacity(0.07)
                                        : const Color(0xFF05050A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? cyan.withOpacity(0.5)
                                          : borderNeon,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Extension badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _extColor(entry.ext).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: _extColor(entry.ext).withOpacity(0.4)),
                                        ),
                                        child: Text('.${entry.ext}',
                                            style: TextStyle(
                                                color: _extColor(entry.ext),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      const SizedBox(width: 14),
                                      // Name + path
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(entry.fullName,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14)),
                                            if (entry.path.isNotEmpty)
                                              Text(entry.path,
                                                  style: TextStyle(
                                                      color: textMuted.withOpacity(0.5),
                                                      fontSize: 10,
                                                      fontFamily: 'monospace'),
                                                  overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      // Checkbox
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? cyan
                                              : Colors.transparent,
                                          border: Border.all(
                                              color: isSelected ? cyan : borderNeon,
                                              width: 1.5),
                                        ),
                                        child: isSelected
                                            ? const Icon(Icons.check_rounded,
                                                color: Colors.black, size: 14)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            // Open selected button (only when items selected)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _selected.isNotEmpty
                                  ? SizedBox(
                                      width: double.infinity,
                                      key: const ValueKey('open_btn'),
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.launch_rounded,
                                            color: Colors.black, size: 18),
                                        label: Text(
                                          'Open ${_selected.length} file${_selected.length > 1 ? 's' : ''}',
                                          style: const TextStyle(
                                              color: Colors.black,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.0),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: cyan,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: _openSelected,
                                      ),
                                    )
                                  : const SizedBox.shrink(key: ValueKey('no_btn')),
                            ),
                            const SizedBox(height: 24),
                            Divider(color: borderNeon.withOpacity(0.6)),
                            const SizedBox(height: 24),
                          ],

                          // Action cards
                          Text('START',
                              style: TextStyle(
                                  color: textMuted.withOpacity(0.5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.0)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _actionCard(
                                icon: Icons.add_circle_outline_rounded,
                                title: 'New File',
                                subtitle: 'Create .py .cpp .js',
                                color: purple,
                                onTap: () => widget.onComplete([]),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: _actionCard(
                                icon: Icons.folder_open_rounded,
                                title: 'Open File',
                                subtitle: 'Browse device storage',
                                color: cyan,
                                onTap: () => widget.onComplete([]),
                              )),
                            ],
                          ),

                          // Skip link
                          const SizedBox(height: 32),
                          Center(
                            child: GestureDetector(
                              onTap: () => widget.onComplete([]),
                              child: Text('Skip & open empty editor',
                                  style: TextStyle(
                                      color: textMuted.withOpacity(0.4),
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                      decorationColor: textMuted.withOpacity(0.4))),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
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

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
