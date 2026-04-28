import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/terminal_controller.dart';

class ModernTerminal extends StatefulWidget {
  final TerminalController controller;
  final Function(String) onInput;
  final bool isRunning;
  final VoidCallback onStop;

  const ModernTerminal({
    super.key,
    required this.controller,
    required this.onInput,
    this.isRunning = false,
    required this.onStop,
  });

  @override
  State<ModernTerminal> createState() => _ModernTerminalState();
}

class _ModernTerminalState extends State<ModernTerminal> with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // When keyboard appears/disappears, metrics change. Scroll to ensure input is visible.
    _scrollToBottom();
  }

  void _onControllerUpdate() {
    // Sync text controller with terminal controller if they diverge (e.g. history or backspace)
    if (_textController.text != widget.controller.currentInput) {
      _textController.text = widget.controller.currentInput;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    }
    setState(() {}); // Crucial: triggers UI rebuild so the input shows up live!
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Delay slightly to allow layout to finish resizing after keyboard appear
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _handleSubmit(String value) {
    final input = widget.controller.submit();
    widget.onInput(input);
    _textController.clear();
    // Removed unfocus() to keep keyboard open for sequential inputs
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF0D0D12);
    final Color textColor = const Color(0xFFE2E8F0);
    final Color accentColor = const Color(0xFF00FF88);

    return GestureDetector(
      onTap: () {
        // If already focused, unfocus first to force a fresh keyboard request
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) _focusNode.requestFocus();
          });
        } else {
          _focusNode.requestFocus();
        }
      },
      child: Container(
        color: bgColor,
        child: Stack(
          children: [
            // Terminal View
            Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.controller.lines.length + 1,
                    itemBuilder: (context, index) {
                      if (index < widget.controller.lines.length) {
                        final line = widget.controller.lines[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            line.text,
                            style: TextStyle(
                              color: line.color ?? textColor,
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        );
                      } else {
                        // Input Line
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '➜ ',
                              style: TextStyle(
                                color: accentColor,
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: widget.controller.currentInput,
                                      style: TextStyle(
                                        color: textColor,
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                    ),
                                    WidgetSpan(
                                      child: TerminalCursor(
                                        color: accentColor,
                                        isFocused: _focusNode.hasFocus,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            ),

            // Hidden TextField placed out of the way to prevent Flutter from auto-scrolling
            // the entire view excessively when the keyboard opens.
            Positioned(
              bottom: 0,
              left: 0,
              child: SizedBox(
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    focusNode: _focusNode,
                    controller: _textController,
                    autofocus: false,
                    scrollPadding: EdgeInsets.zero, // Prevent auto-scroll jumps
                    onChanged: (v) => widget.controller.setInput(v),
                    onSubmitted: _handleSubmit,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TerminalCursor extends StatefulWidget {
  final Color color;
  final bool isFocused;

  const TerminalCursor({
    super.key,
    required this.color,
    required this.isFocused,
  });

  @override
  State<TerminalCursor> createState() => _TerminalCursorState();
}

class _TerminalCursorState extends State<TerminalCursor> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted && widget.isFocused) {
        setState(() => _visible = !_visible);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 16,
      color: widget.isFocused && _visible ? widget.color : Colors.transparent,
    );
  }
}
