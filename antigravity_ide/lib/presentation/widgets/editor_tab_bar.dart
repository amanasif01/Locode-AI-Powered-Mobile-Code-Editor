import 'package:flutter/material.dart';
import '../../domain/ide_file.dart';

class EditorTabBar extends StatelessWidget {
  final List<IDEFile> files;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onTabClosed;
  final bool isDarkMode;

  const EditorTabBar({
    super.key,
    required this.files,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onTabClosed,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    final Color bgPureBlack = isDarkMode ? const Color(0xFF000000) : const Color(0xFFF8FAFC);
    final Color borderNeon = isDarkMode ? const Color(0xFF1A1A24) : const Color(0xFFE2E8F0);
    final Color cyanAccent = isDarkMode ? const Color(0xFF00FFFF) : const Color(0xFF0EA5E9);
    final Color textMuted = isDarkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    final Color tabBg = isDarkMode ? const Color(0xFF0A0A12) : const Color(0xFFFFFFFF);

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 8.0),
      color: bgPureBlack,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: tabBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderNeon),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(files.length, (index) {
              final isSelected = index == currentIndex;
              final isDirty = files[index].isDirty;
              return GestureDetector(
                onTap: () => onTabSelected(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  margin: const EdgeInsets.all(2.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: isSelected
                        ? LinearGradient(colors: [
                            cyanAccent.withOpacity(0.15),
                            const Color(0xFF9D00FF).withOpacity(0.15)
                          ])
                        : null,
                    border: isSelected
                        ? Border.all(color: cyanAccent.withOpacity(0.5))
                        : Border.all(color: Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        files[index].fullName,
                        style: TextStyle(
                          color: isSelected ? cyanAccent : textMuted,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13,
                          letterSpacing: 1.0,
                        ),
                      ),
                      // Unsaved indicator
                      if (isDirty) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? cyanAccent : textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => onTabClosed(index),
                        child: Icon(Icons.close_rounded,
                            size: 14,
                            color: isSelected ? cyanAccent : textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
