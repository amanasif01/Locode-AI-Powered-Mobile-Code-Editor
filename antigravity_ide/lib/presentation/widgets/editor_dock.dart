import 'package:flutter/material.dart';

class EditorDock extends StatelessWidget {
  final VoidCallback onToggleTerminal;
  final VoidCallback onToggleLocodeAi;
  final bool isTerminalOpen;
  final bool isLocodeAiOpen;
  final bool isDarkMode;

  const EditorDock({
    super.key,
    required this.onToggleTerminal,
    required this.onToggleLocodeAi,
    required this.isTerminalOpen,
    required this.isLocodeAiOpen,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderNeon = isDarkMode ? const Color(0xFF262626) : const Color(0xFFE2E8F0);
    final Color textMuted = isDarkMode ? const Color(0xFF888888) : const Color(0xFF64748B);
    final Color bgDark = isDarkMode ? const Color(0xFF111111) : const Color(0xFFFFFFFF);

    return Container(
      decoration: BoxDecoration(
        color: bgDark,
        border: Border(top: BorderSide(color: borderNeon, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            NeonAction(
              icon: Icons.terminal_rounded,
              label: 'OUTPUT',
              baseColor: isTerminalOpen ? const Color(0xFF00FFFF) : textMuted,
              isActive: isTerminalOpen,
              onTap: onToggleTerminal,
            ),
            NeonAction(
              icon: Icons.auto_awesome_rounded,
              label: 'AI ASSIST',
              baseColor: isLocodeAiOpen ? const Color(0xFF00FFFF) : textMuted,
              isActive: isLocodeAiOpen,
              onTap: onToggleLocodeAi,
            ),
          ],
        ),
      ),
    );
  }
}

class NeonAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color baseColor;
  final VoidCallback onTap;
  final bool isActive;

  const NeonAction({
    super.key,
    required this.icon,
    required this.label,
    required this.baseColor,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: baseColor.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isActive ? baseColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: baseColor, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: baseColor,
                    letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }
}
