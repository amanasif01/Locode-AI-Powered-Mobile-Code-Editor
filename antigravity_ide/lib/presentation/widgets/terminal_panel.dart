import 'package:flutter/material.dart';
import 'modern_terminal.dart';
import '../../domain/terminal_controller.dart';

class TerminalPanel extends StatelessWidget {
  final bool isOpen;
  final TerminalController controller;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final bool isDarkMode;
  final bool isRunning;
  final VoidCallback? onClear;
  final Function(String) onInput;

  const TerminalPanel({
    super.key,
    required this.isOpen,
    required this.controller,
    required this.onToggle,
    required this.onStop,
    this.isDarkMode = true,
    this.isRunning = false,
    this.onClear,
    required this.onInput,
  });

  @override
  Widget build(BuildContext context) {
    final Color headerColor = isDarkMode ? const Color(0xFF0F0F16) : const Color(0xFFE2E8F0);
    final Color borderColor = isDarkMode ? const Color(0xFF333344) : const Color(0xFFCBD5E1);
    final Color textColor = isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final Color accentColor = const Color(0xFF00FF88);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      height: isOpen ? (MediaQuery.of(context).viewInsets.bottom > 0 ? 130 : 220) : 0,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
      ),
      child: isOpen
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Terminal Header Strip
                Container(
                  color: headerColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal_sharp, color: accentColor, size: 14),
                          const SizedBox(width: 10),
                          Text(
                            'INTERACTIVE TERMINAL',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: textColor,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (isRunning)
                            Container(
                              margin: const EdgeInsets.only(right: 12),
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00FF88),
                                shape: BoxShape.circle,
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              Icons.stop_circle_rounded,
                              size: 20,
                              color: isRunning ? const Color(0xFFFF5555) : textColor.withOpacity(0.2),
                            ),
                            tooltip: 'Stop Execution',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: isRunning ? onStop : null,
                          ),
                          const SizedBox(width: 14),
                          IconButton(
                            icon: Icon(Icons.delete_sweep_rounded, size: 20, color: textColor.withOpacity(0.5)),
                            tooltip: 'Clear Console',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onClear,
                          ),
                          const SizedBox(width: 14),
                          IconButton(
                            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: textColor),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onToggle,
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                // Modern Terminal View
                Expanded(
                  child: ModernTerminal(
                    controller: controller,
                    isRunning: isRunning,
                    onStop: onStop,
                    onInput: onInput,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
