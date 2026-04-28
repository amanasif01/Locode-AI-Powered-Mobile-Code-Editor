import 'package:flutter/material.dart';
import '../../domain/diff_engine.dart';

class InteractiveDiffEditor extends StatefulWidget {
  final String originalCode;
  final String newCode;
  final ValueChanged<String> onApply;
  final VoidCallback onCancel;
  final bool isDarkMode;

  const InteractiveDiffEditor({
    Key? key,
    required this.originalCode,
    required this.newCode,
    required this.onApply,
    required this.onCancel,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  State<InteractiveDiffEditor> createState() => _InteractiveDiffEditorState();
}

class _InteractiveDiffEditorState extends State<InteractiveDiffEditor> {
  late List<DiffLine> _diffLines;
  final List<DiffHunk> _hunks = [];

  @override
  void initState() {
    super.initState();
    _computeHunks();
  }

  void _computeHunks() {
    _diffLines = DiffEngine.computeDiff(widget.originalCode, widget.newCode);
    
    // Group contiguous changes into hunks for easy Accept/Reject
    DiffHunk? currentHunk;
    for (final line in _diffLines) {
      if (line.type != DiffType.unchanged) {
        currentHunk ??= DiffHunk();
        currentHunk.lines.add(line);
      } else {
        if (currentHunk != null) {
          _hunks.add(currentHunk);
          currentHunk = null;
        }
      }
    }
    if (currentHunk != null) {
      _hunks.add(currentHunk);
    }
  }

  void _acceptHunk(DiffHunk hunk) {
    setState(() => hunk.isAccepted = true);
  }

  void _rejectHunk(DiffHunk hunk) {
    setState(() => hunk.isRejected = true);
  }

  void _acceptAll() {
    for (var hunk in _hunks) {
      hunk.isAccepted = true;
      hunk.isRejected = false;
    }
    _applyChanges();
  }

  void _applyChanges() {
    final buffer = StringBuffer();
    for (var i = 0; i < _diffLines.length; i++) {
      final line = _diffLines[i];
      if (line.type == DiffType.unchanged) {
        buffer.writeln(line.text);
      } else {
        // Find which hunk this line belongs to
        final hunk = _hunks.firstWhere((h) => h.lines.contains(line));
        if (hunk.isAccepted) {
          if (line.type == DiffType.insert) buffer.writeln(line.text);
        } else if (hunk.isRejected) {
          if (line.type == DiffType.delete) buffer.writeln(line.text);
        } else {
          // If pending, default to old behavior (keep delete, ignore insert)
          if (line.type == DiffType.delete) buffer.writeln(line.text);
        }
      }
    }
    
    // Remove last newline if needed
    String result = buffer.toString();
    if (result.endsWith('\n')) result = result.substring(0, result.length - 1);
    
    widget.onApply(result);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDarkMode ? const Color(0xFF000000) : Colors.white;
    final fg = widget.isDarkMode ? const Color(0xFFD4D4D4) : Colors.black87;

    return Container(
      color: bg,
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: widget.isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF3F3F3),
              border: Border(bottom: BorderSide(color: widget.isDarkMode ? Colors.black : Colors.grey.shade300)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.difference, size: 16, color: Color(0xFF00FF88)),
                  const SizedBox(width: 8),
                  Text('Review', style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: Text('Cancel', style: TextStyle(color: widget.isDarkMode ? Colors.white54 : Colors.black54)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.done_all, size: 14, color: Colors.black),
                    label: const Text('Accept All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF88),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _acceptAll,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _applyChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          
          // Diff View
          Expanded(
            child: ListView.builder(
              itemCount: _diffLines.length,
              itemBuilder: (context, index) {
                final line = _diffLines[index];
                
                if (line.type == DiffType.unchanged) {
                  return _buildLineRow(line.text, ' ', fg, Colors.transparent, fg.withOpacity(0.5), line.originalLineNumber);
                }

                final hunk = _hunks.firstWhere((h) => h.lines.contains(line));
                if (hunk.isAccepted) {
                  if (line.type == DiffType.delete) return const SizedBox.shrink();
                  // Decolorize to show it's resolved and accepted
                  return _buildLineRow(line.text, ' ', fg, Colors.transparent, fg.withOpacity(0.5), line.newLineNumber);
                }
                if (hunk.isRejected) {
                  if (line.type == DiffType.insert) return const SizedBox.shrink();
                  // Decolorize to show it's resolved and reverted
                  return _buildLineRow(line.text, ' ', fg, Colors.transparent, fg.withOpacity(0.5), line.originalLineNumber);
                }

                // Pending state
                final isFirstInHunk = hunk.lines.first == line;
                final isInsert = line.type == DiffType.insert;
                final bgColor = isInsert ? const Color(0x3300FF88) : const Color(0x33FF4444);
                final accentColor = isInsert ? const Color(0xFF00FF88) : const Color(0xFFFF4444);

                Widget lineWidget = _buildLineRow(line.text, isInsert ? '+' : '-', fg, bgColor, accentColor, isInsert ? line.newLineNumber : line.originalLineNumber);

                if (isFirstInHunk) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: bgColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _actionBtn('Keep', Icons.check, const Color(0xFF00FF88), () => _acceptHunk(hunk)),
                            const SizedBox(width: 8),
                            _actionBtn('Discard', Icons.close, const Color(0xFFFF4444), () => _rejectHunk(hunk)),
                          ],
                        ),
                      ),
                      lineWidget,
                    ],
                  );
                }

                return lineWidget;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color accentColor, VoidCallback onTap) {
    final Color blueTheme = const Color(0xFF3B82F6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: blueTheme,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLineRow(String text, String prefix, Color textCol, Color bgCol, Color prefixCol, int lineNum) {
    return Container(
      color: bgCol,
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              lineNum >= 0 ? (lineNum + 1).toString() : '',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: textCol.withOpacity(0.3)),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Text(prefix, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: prefixCol, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.isEmpty ? ' ' : text,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textCol, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}
