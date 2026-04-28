import 'package:flutter/material.dart';

class EditorStatusBar extends StatelessWidget {
  final String latestOutput;
  final String activeExtension; 
  final bool isDarkMode;

  const EditorStatusBar({
    super.key, 
    required this.latestOutput, 
    required this.activeExtension,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgPureBlack = isDarkMode ? const Color(0xFF000000) : const Color(0xFFF1F5F9);
    final Color borderNeon = isDarkMode ? const Color(0xFF1A1A24) : const Color(0xFFE2E8F0);
    final Color textMuted = isDarkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    final Color cyanAccent = isDarkMode ? const Color(0xFF00FFFF) : const Color(0xFF0EA5E9);
    final Color primaryAccent = isDarkMode ? const Color(0xFF9D00FF) : const Color(0xFF8B5CF6);
    
    final bool isRunning = latestOutput == "Running...";
    
    String engineName = "SYSTEM OFFLINE";
    if (activeExtension == 'py') engineName = "PYTHON_V3.13 // UTF-8";
    if (activeExtension == 'cpp') engineName = "GCC_V14 // WASM";
    if (activeExtension == 'js') engineName = "ES6_JAVASCRIPT // V8";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: bgPureBlack,
        border: Border(top: BorderSide(color: borderNeon, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.data_object_rounded, size: 14, color: textMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    engineName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600, letterSpacing: 1.0),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? primaryAccent : cyanAccent,
                  boxShadow: [
                    BoxShadow(color: isRunning ? primaryAccent : cyanAccent, blurRadius: 8),
                  ]
                ),
              ),
              const SizedBox(width: 8),
            ],
          )
        ],
      ),
    );
  }
}
