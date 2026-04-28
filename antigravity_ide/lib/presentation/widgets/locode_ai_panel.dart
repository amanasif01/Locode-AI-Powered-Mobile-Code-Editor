import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class LocodeAiPanel extends StatefulWidget {
  final bool isOpen;
  final bool isDarkMode;
  final VoidCallback onClose;
  final String activeFileName;
  final Future<String> Function()? getFileContent;
  final void Function(String)? onApplyCode;
  final void Function(String)? onReplaceFile;
  final void Function(String)? onAiSuggestion;

  const LocodeAiPanel({
    super.key,
    required this.isOpen,
    required this.isDarkMode,
    required this.onClose,
    required this.activeFileName,
    this.getFileContent,
    this.onApplyCode,
    this.onReplaceFile,
    this.onAiSuggestion,
  });

  @override
  State<LocodeAiPanel> createState() => _LocodeAiPanelState();
}

class _LocodeAiPanelState extends State<LocodeAiPanel>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  bool _isComputing = false;
  bool _abortGeneration = false;
  bool _inputHasText = false;
  double _savedScrollOffset = 0.0;
  bool _includeContext = true;

  // Groq API key (Redacted)
  final String _groqApiKey = const String.fromEnvironment('GROQ_API_KEY', defaultValue: '');

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();

    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _inputHasText) setState(() => _inputHasText = hasText);
    });

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        _savedScrollOffset = _scrollController.offset;
      }
    });

    _messages.add(ChatMessage(text: "How can I help you build today?", isUser: false));
  }

  void _addSystemMessage(String text) {
    if (!mounted) return;
    setState(() => _messages.add(ChatMessage(text: text, isUser: false)));
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant LocodeAiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _fadeController.reset();
      _fadeController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _savedScrollOffset > 0) {
          _scrollController.jumpTo(_savedScrollOffset);
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isComputing) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isComputing = true;
      _abortGeneration = false;
    });
    _textController.clear();
    _scrollToBottom();

    final liveContent = (_includeContext && widget.getFileContent != null)
        ? (await widget.getFileContent!.call())
        : '';

    try {
      String systemPrompt;
      if (_includeContext && widget.activeFileName.isNotEmpty) {
        String lang = 'code';
        if (widget.activeFileName.endsWith('.py')) lang = 'Python';
        else if (widget.activeFileName.endsWith('.c')) lang = 'C';
        else if (widget.activeFileName.endsWith('.cpp')) lang = 'C++';
        else if (widget.activeFileName.endsWith('.js')) lang = 'JavaScript';
        else if (widget.activeFileName.endsWith('.dart')) lang = 'Dart';
        
        final contentSection = liveContent.isNotEmpty 
          ? '\n\nCurrent file content:\n```$lang\n$liveContent\n```'
          : '\n\nThe current file is empty.';

        systemPrompt = 'You are an expert coding assistant for Locode. The user is editing a $lang file named "${widget.activeFileName}". $contentSection\n\nProvide concise and accurate answers. Only write code if the user explicitly asks for code, asks for a solution, or asks you to modify the file. If you write code, it must be valid $lang code enclosed in a markdown code block.';
      } else {
        systemPrompt = 'You are an expert coding assistant for Locode. Provide concise and accurate answers. Only write code if the user explicitly asks for it. Use markdown code blocks when writing code.';
      }

      final chatHistory = _messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
          .toList();

      if (chatHistory.isEmpty || chatHistory.last['role'] != 'user') {
        chatHistory.add({'role': 'user', 'content': text});
      }

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...chatHistory,
          ],
          'max_tokens': 2048,
          'temperature': 0.3,
        }),
      ).timeout(const Duration(seconds: 30));

      if (_abortGeneration || !mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = (data['choices']?[0]?['message']?['content'] ?? '').toString();
        setState(() => _messages.add(ChatMessage(text: reply, isUser: false)));
      } else if (response.statusCode == 401) {
        setState(() => _messages.add(ChatMessage(text: '⚠ Invalid Groq API key.', isUser: false)));
      } else {
        final body = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
        setState(() => _messages.add(ChatMessage(text: '⚠ Groq error ${response.statusCode}: $body', isUser: false)));
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _messages.add(ChatMessage(text: '⚠ Request timed out. Check your connection.', isUser: false)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(ChatMessage(text: '⚠ Network error: $e', isUser: false)));
      }
    } finally {
      if (mounted) {
        setState(() => _isComputing = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final bool dark = widget.isDarkMode;
    final Color glassBg = dark ? const Color(0x99000000) : const Color(0xB2FFFFFF);
    final Color border = dark ? const Color(0x22FFFFFF) : const Color(0x1F000000);
    final Color textPrimary = dark ? const Color(0xFFECECEC) : const Color(0xFF111111);
    final Color textMuted = dark ? const Color(0xFF888888) : const Color(0xFF666666);
    final Color inputBg = dark ? const Color(0x44FFFFFF) : const Color(0x0A000000);

    return FadeTransition(
      opacity: _fadeController,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
            CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic)),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              height: 400,
              decoration: BoxDecoration(
                color: glassBg,
                border: Border(top: BorderSide(color: border, width: 0.5)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 40)],
              ),
              child: Column(
                children: [
                  _buildHeader(textPrimary, textMuted, dark),
                  Expanded(child: _buildMessages(textPrimary, textMuted, border, dark)),
                  _buildInput(textPrimary, textMuted, border, inputBg, dark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────
  Widget _buildHeader(Color text, Color muted, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dark ? Colors.white10 : Colors.black12, width: 0.5)),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isComputing ? const Color(0xFF007AFF) : const Color(0xFF00FF88),
              boxShadow: [BoxShadow(color: _isComputing ? const Color(0xFF007AFF) : const Color(0xFF00FF88), blurRadius: 7)],
            ),
          ),
          const SizedBox(width: 10),
          const Text('Locode AI', style: TextStyle(fontSize: 13, color: Color(0xFF00FF88), fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          
          if (widget.activeFileName.isNotEmpty) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: dark ? Colors.white10 : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(widget.activeFileName, style: TextStyle(fontSize: 10, color: muted, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(onTap: widget.onClose, child: Icon(Icons.close_rounded, size: 18, color: muted)),
        ],
      ),
    );
  }

  // ── MESSAGES ──────────────────────────────────────────────────────────
  Widget _buildMessages(Color text, Color muted, Color border, bool dark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _messages.length + (_isComputing ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (_isComputing && i == _messages.length) return _buildTypingIndicator(muted, dark);
        final msg = _messages[i];
        return msg.isUser ? _buildUserMessage(msg.text, text, muted, dark) : _buildAiMessage(msg.text, text, border, dark);
      },
    );
  }

  Widget _buildTypingIndicator(Color muted, bool dark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Icon(Icons.auto_awesome, size: 18, color: muted),
        const SizedBox(width: 12),
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: muted)),
        const SizedBox(width: 10),
        Text('Generating…', style: TextStyle(color: muted, fontSize: 12)),
      ]),
    );
  }

  Widget _buildUserMessage(String text, Color textC, Color muted, bool dark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E2E2),
                borderRadius: BorderRadius.circular(14).copyWith(topRight: Radius.zero),
              ),
              child: SelectableText(text, style: TextStyle(color: textC, fontSize: 13.5, height: 1.5)),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 12,
            backgroundColor: dark ? Colors.white12 : Colors.black12,
            child: Icon(Icons.person, size: 14, color: textC),
          )
        ],
      ),
    );
  }

  Widget _buildAiMessage(String text, Color textC, Color border, bool dark) {
    final segments = _parseMessage(text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.auto_awesome, size: 18, color: Color(0xFF00FF88)),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: segments.map((seg) {
                if (seg['type'] == 'code') {
                  return _buildCodeBlock(seg['content']!, seg['lang'] ?? '', border, dark);
                } else {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SelectableText(
                      seg['content']!,
                      style: TextStyle(color: textC, fontSize: 13.5, height: 1.6, fontWeight: FontWeight.w400),
                    ),
                  );
                }
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String code, String lang, Color border, bool dark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14, top: 4),
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F0F0F) : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 0.5)),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            ),
            child: Row(children: [
              const Icon(Icons.code_rounded, size: 12, color: Color(0xFF00FF88)),
              const SizedBox(width: 6),
              Text(lang.isEmpty ? 'code' : lang, style: TextStyle(fontSize: 11, color: dark ? Colors.white60 : Colors.black54, fontFamily: 'monospace')),
              const Spacer(),
            ]),
          ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: dark ? const Color(0xFFD4D4D4) : const Color(0xFF24292E), height: 1.5)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: border, width: 0.5))),
            child: Row(
              children: [
                if (widget.onAiSuggestion != null) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onAiSuggestion!('```\n$code\n```'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white),
                            SizedBox(width: 5),
                            Text('Implement Solution', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.onApplyCode != null) ...[
                  _actionChip(Icons.input_rounded, 'Insert', const Color(0xFF00D4FF), dark, () => widget.onApplyCode!(code)),
                  const SizedBox(width: 10),
                ],
                _actionChip(Icons.copy_rounded, 'Copy', dark ? Colors.white38 : Colors.black38, dark, () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!'), duration: Duration(seconds: 1)));
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, Color color, bool dark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ── INPUT ─────────────────────────────────────────────────────────────
  Widget _buildInput(Color text, Color muted, Color border, Color inputBg, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(color: dark ? const Color(0x33000000) : const Color(0x11000000)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            SizedBox(
              height: 22, width: 22,
              child: Checkbox(
                value: _includeContext,
                onChanged: (val) => setState(() => _includeContext = val ?? true),
                activeColor: const Color(0xFF00FF88),
                checkColor: Colors.black,
                side: BorderSide(color: muted, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Text('Send file context', style: TextStyle(fontSize: 11, color: muted)),
          ]),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          style: TextStyle(color: text, fontSize: 13.5, height: 1.5),
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: 'Ask something…',
                            hintStyle: TextStyle(color: muted, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: GestureDetector(
                          onTap: () {
                            if (_isComputing) {
                              setState(() {
                                _abortGeneration = true;
                                _isComputing = false;
                              });
                            } else if (_inputHasText) {
                              _sendMessage();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: (_inputHasText || _isComputing)
                                  ? (dark ? Colors.white : Colors.black)
                                  : (dark ? Colors.white12 : Colors.black12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _isComputing
                                ? Icon(Icons.stop_rounded, size: 16, color: dark ? Colors.black : Colors.white)
                                : Icon(Icons.arrow_upward_rounded, size: 16, color: _inputHasText ? (dark ? Colors.black : Colors.white) : (dark ? Colors.white30 : Colors.black38)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── CODE PARSER ───────────────────────────────────────────────────────
  List<Map<String, String>> _parseMessage(String text) {
    final List<Map<String, String>> segments = [];
    // Flexible regex for ``` or ''' blocks
    final regex = RegExp(r'(?:```|\'\'\')(\w*)[\n\s]*([\s\S]*?)(?:```|\'\'\')');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        final t = text.substring(lastEnd, match.start).trim();
        if (t.isNotEmpty) segments.add({'type': 'text', 'content': t});
      }
      
      final rawContent = match.group(2) ?? '';
      segments.add({
        'type': 'code',
        'lang': match.group(1) ?? '',
        'content': _sanitizeCode(rawContent),
      });
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final t = text.substring(lastEnd).trim();
      if (t.isNotEmpty) segments.add({'type': 'text', 'content': t});
    }

    if (segments.isEmpty) segments.add({'type': 'text', 'content': text});
    return segments;
  }

  String _sanitizeCode(String code) {
    String s = code.trim();
    // Double check to strip any leaked markers or language tags
    if (s.startsWith('```')) s = s.replaceFirst(RegExp(r'^```\w*\s*'), '');
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    if (s.startsWith("'''")) s = s.replaceFirst(RegExp(r"^'''\w*\s*"), '');
    if (s.endsWith("'''")) s = s.substring(0, s.length - 3);
    return s.trim();
  }
}
