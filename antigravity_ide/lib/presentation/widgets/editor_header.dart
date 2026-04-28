import 'package:flutter/material.dart';

class EditorHeader extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onSaveFile;
  final VoidCallback onSaveAs;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final VoidCallback onToggleDarkMode;
  final VoidCallback? onTogglePythonEngine;
  final bool isPythonOnline;
  final bool isRunning;
  final bool hasActiveFile;
  final String activeExtension;
  final bool isDarkMode;

  const EditorHeader({
    super.key,
    required this.onMenuTap,
    required this.onSaveFile,
    required this.onSaveAs,
    required this.onRun,
    required this.onStop,
    required this.onToggleDarkMode,
    this.onTogglePythonEngine,
    this.isPythonOnline = false,
    this.isRunning = false,
    this.hasActiveFile = false,
    this.activeExtension = '',
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgPureBlack = isDarkMode ? const Color(0xFF111111) : const Color(0xFFF8FAFC);
    final Color borderNeon = isDarkMode ? const Color(0xFF262626) : const Color(0xFFE2E8F0);
    final Color iconColor = isDarkMode ? const Color(0xFF888888) : const Color(0xFF64748B);
    final Color cyanAccent = isDarkMode ? const Color(0xFF00FFFF) : const Color(0xFF0EA5E9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: bgPureBlack,
        border: Border(bottom: BorderSide(color: borderNeon, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.menu_rounded, color: cyanAccent, size: 24),
            onPressed: onMenuTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            tooltip: 'Files Menu',
          ),
          const Spacer(),

          LayoutBuilder(builder: (ctx, constraints) {
            final parentWidth = MediaQuery.of(ctx).size.width;
            if (parentWidth < 300) return const SizedBox.shrink();
            return GestureDetector(
              onTap: onMenuTap,
              child: Text(
                'LOCODE',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: isDarkMode ? Colors.white : const Color(0xFF0EA5E9)),
              ),
            );
          }),
          const Spacer(),
          if (hasActiveFile) ...[
            if (activeExtension == 'py' && onTogglePythonEngine != null) ...[
              GestureDetector(
                onTap: onTogglePythonEngine,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPythonOnline ? const Color(0xFF00FF88).withOpacity(0.15) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isPythonOnline ? const Color(0xFF00FF88) : Colors.white24, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(isPythonOnline ? Icons.cloud_done_rounded : Icons.offline_bolt_rounded, size: 12, color: isPythonOnline ? const Color(0xFF00FF88) : Colors.white60),
                      const SizedBox(width: 6),
                      Text(
                        isPythonOnline ? 'ONLINE' : 'LIGHT',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isPythonOnline ? const Color(0xFF00FF88) : Colors.white60, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            IconButton(
              icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: isRunning ? const Color(0xFFEF4444) : const Color(0xFF3B82F6), size: 24),
              onPressed: isRunning ? onStop : onRun,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: isRunning ? 'Stop' : 'Run',
            ),
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: Color(0xFF475569), size: 22),
            padding: EdgeInsets.zero,
            color: const Color(0xFF0F0F16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF1A1A24)),
            ),
            onSelected: (val) {
              if (val == 'save') onSaveFile();
              if (val == 'saveas') onSaveAs();
              if (val == 'darkmode') onToggleDarkMode();
            },
            itemBuilder: (context) => [
              _menuItem('save', Icons.save_alt_rounded, 'Save',
                  isDarkMode ? Colors.white70 : const Color(0xFF0EA5E9)),
              _menuItem('saveas', Icons.drive_file_rename_outline_rounded,
                  'Save As…', isDarkMode ? Colors.white70 : const Color(0xFF0EA5E9)),
              const PopupMenuDivider(height: 1),
              _menuItem('darkmode', isDarkMode ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, 
                  'Dark Mode', isDarkMode ? Colors.white70 : const Color(0xFF64748B)),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: color == const Color(0xFF475569)
                    ? Colors.white54
                    : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}


