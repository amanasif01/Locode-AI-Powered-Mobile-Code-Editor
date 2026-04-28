import 'package:flutter/material.dart';

/// Code editor with a line-number gutter that is always pixel-perfectly aligned.
///
/// Key insight: [InputDecoration.collapsed] removes ALL InputDecorator padding,
/// so the TextField text starts at exactly y=0.  The gutter [CustomPainter]
/// uses the same [TextPainter] metrics, so numbers and lines are always flush.
class CodeEditorWithGutter extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final UndoHistoryController undoController;

  static const _textStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 15,
    height: 1.6,
    color: Color(0xFFE2E8F0),
  );

  static const _gutterWidth = 48.0;
  static const _topPad     = 16.0;
  static const _leftPad    = 12.0;
  static const _rightPad   = 16.0;

  const CodeEditorWithGutter({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.undoController,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Width the TextField uses for its text layout
      final textWidth = constraints.maxWidth - _gutterWidth - _leftPad - _rightPad;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gutter ──────────────────────────────────────────────────────
          Container(
            width: _gutterWidth,
            decoration: const BoxDecoration(
              color: Color(0xFF000000),
              border: Border(
                right: BorderSide(color: Color(0xFF1A1A28), width: 1),
              ),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: _topPad),
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  final h = _measure(controller.text, textWidth);
                  return CustomPaint(
                    size: Size(_gutterWidth, h),
                    painter: _GutterPainter(
                      text: controller.text,
                      textStyle: _textStyle,
                      textWidth: textWidth,
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Editor ──────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                  _leftPad, _topPad, _rightPad, 80),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                undoController: undoController,
                maxLines: null,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                cursorColor: const Color(0xFF9D00FF),
                cursorWidth: 3,
                cursorRadius: const Radius.circular(2),
                style: _textStyle,
                textAlignVertical: TextAlignVertical.top,
                // collapsed = zero InputDecorator padding → text at y=0
                decoration: const InputDecoration.collapsed(hintText: ''),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ),
        ],
      );
    });
  }

  static double _measure(String text, double width) {
    final tp = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return tp.height;
  }
}

// ── Gutter painter ────────────────────────────────────────────────────────────

class _GutterPainter extends CustomPainter {
  final String text;
  final TextStyle textStyle;
  final double textWidth;

  static const _numStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.0,
    color: Color(0x5A94A3B8),  // slate-400 @ ~35 %
  );

  const _GutterPainter({
    required this.text,
    required this.textStyle,
    required this.textWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = text.isEmpty ? ' ' : text;

    // Layout using the exact same text-width as the TextField
    final fullPainter = TextPainter(
      text: TextSpan(text: src, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);

    final metrics = fullPainter.computeLineMetrics();
    if (metrics.isEmpty) return;

    final logicalLines = text.split('\n');
    int vi = 0;

    for (int li = 0; li < logicalLines.length; li++) {
      if (vi >= metrics.length) break;

      final m = metrics[vi];
      // Optically center the number in the code's line box
      final lineBoxTop = m.baseline - m.ascent;
      _drawNum(canvas, size.width, li + 1, lineBoxTop, m.height);

      // Count how many visual lines this logical line occupies (wrapping)
      final lText = logicalLines[li];
      if (lText.isEmpty) {
        vi += 1;
      } else {
        final lp = TextPainter(
          text: TextSpan(text: lText, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: textWidth);
        vi += lp.computeLineMetrics().length;
      }
    }
  }

  void _drawNum(Canvas canvas, double gutterW, int n, double lineBoxTop, double lineBoxHeight) {
    final tp = TextPainter(
      text: TextSpan(text: '$n', style: _numStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: gutterW - 8);

    // Center the number within the code line's height
    final yPos = lineBoxTop + ((lineBoxHeight - tp.height) / 2);

    // Right-align with 8 px right margin
    tp.paint(canvas, Offset(gutterW - 8 - tp.width, yPos));
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.text != text || old.textWidth != textWidth;
}
