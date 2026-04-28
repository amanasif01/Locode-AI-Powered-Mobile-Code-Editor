import 'package:flutter/material.dart';

class LocodeNativeController extends TextEditingController {
  Map<String, TextStyle> styles;
  String language;

  // ── Undo / Redo History ───────────────────────────────────────────────────
  final List<TextEditingValue> _undoStack = [];
  final List<TextEditingValue> _redoStack = [];
  static const int _maxStackSize = 100;
  
  // Track if we are currently performing an undo/redo to avoid recursion
  bool _isUndoingOrRedoing = false;
  // Track previous text for change detection
  TextEditingValue _lastCheckpointValue = TextEditingValue.empty;

  LocodeNativeController({required this.styles, required this.language}) : super() {
    clearUndoHistory();
  }

  void undo() {
    if (_undoStack.length <= 1) return;
    _isUndoingOrRedoing = true;
    
    // Save current to redo stack before popping from undo
    _redoStack.add(value);
    if (_redoStack.length > _maxStackSize) _redoStack.removeAt(0);

    _undoStack.removeLast(); // current state
    final previous = _undoStack.last;
    value = previous;
    _lastCheckpointValue = previous;
    
    _isUndoingOrRedoing = false;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _isUndoingOrRedoing = true;

    final next = _redoStack.removeLast();
    _undoStack.add(next);
    if (_undoStack.length > _maxStackSize) _undoStack.removeAt(0);
    
    value = next;
    _lastCheckpointValue = next;

    _isUndoingOrRedoing = false;
    notifyListeners();
  }

  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  set value(TextEditingValue newValue) {
    if (!_isUndoingOrRedoing) {
      _handleUndoLogic(newValue);
    }
    
    // ── Original Logic (Auto-brackets / Indentation) ──────────────────────
    if (newValue.text.length == value.text.length + 1 && !_isUndoingOrRedoing) {
      final int cursorIdx = newValue.selection.end;
      if (cursorIdx > 0) {
        final String lastChar = newValue.text[cursorIdx - 1];
        final Map<String, String> brackets = {
          '{': '}', '[': ']', '(': ')', '"': '"', "'": "'",
        };

        if (brackets.containsKey(lastChar)) {
          final String closing = brackets[lastChar]!;
          final String updatedText = newValue.text.substring(0, cursorIdx) +
              closing + newValue.text.substring(cursorIdx);
          final resValue = newValue.copyWith(
            text: updatedText,
            selection: TextSelection.collapsed(offset: cursorIdx),
          );
          super.value = resValue;
          return;
        }

        if (lastChar == '\n') {
          final lines = newValue.text.substring(0, cursorIdx - 1).split('\n');
          if (lines.isNotEmpty) {
            final lastLine = lines.last;
            final indentMatch = RegExp(r'^(\s*)').firstMatch(lastLine);
            String indent = indentMatch?.group(1) ?? '';
            if (language == 'py' && lastLine.trim().endsWith(':')) {
              indent += '    ';
            }
            if (indent.isNotEmpty) {
              final String updatedText = newValue.text.substring(0, cursorIdx) +
                  indent + newValue.text.substring(cursorIdx);
              final resValue = newValue.copyWith(
                text: updatedText,
                selection: TextSelection.collapsed(offset: cursorIdx + indent.length),
              );
              super.value = resValue;
              return;
            }
          }
        }
      }
    }
    super.value = newValue;
  }

  void _handleUndoLogic(TextEditingValue newValue) {
    // Only push to stack if text changed meaningfully
    if (newValue.text == _lastCheckpointValue.text) return;

    final String oldText = _lastCheckpointValue.text;
    final String newText = newValue.text;
    
    bool shouldPush = false;

    // Push conditions:
    // 1. Space or Newline typed
    if (newText.length > oldText.length && newValue.selection.start > 0) {
      try {
        final String added = newText.substring(newValue.selection.start - 1, newValue.selection.start);
        if (added == ' ' || added == '\n' || added == '\t') {
          shouldPush = true;
        }
      } catch (_) {
        // Fallback for edge cases where selection might be weird
      }
    }
    
    // 2. Significant change (Paste / Multi-delete)
    final diff = (newText.length - oldText.length).abs();
    if (diff > 1) {
      shouldPush = true;
    }

    // 3. Deletion after typing
    if (newText.length < oldText.length && oldText.isNotEmpty) {
       // Optional: could chunk deletions too
       shouldPush = true; 
    }

    if (shouldPush) {
      _undoStack.add(newValue);
      if (_undoStack.length > _maxStackSize) _undoStack.removeAt(0);
      _redoStack.clear();
      _lastCheckpointValue = newValue;
    }
  }

  void clearUndoHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _undoStack.add(value);
    _lastCheckpointValue = value;
    _isUndoingOrRedoing = false;
  }
  
  TextSpan? _cachedTextSpan;
  String? _lastText;
  String? _lastLanguage;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (text == _lastText && language == _lastLanguage && _cachedTextSpan != null) {
      return _cachedTextSpan!;
    }

    final List<TextSpan> children = [];
    final String textContent = text;

    final patterns = _getPatterns(language);
    int lastMatchEnd = 0;
    final matches = patterns.allMatches(text);

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        children.add(TextSpan(text: textContent.substring(lastMatchEnd, match.start), style: style));
      }

      // Each outer group = one token type. Find the first non-null group.
      TextStyle? matchedStyle;
      for (var i = 1; i <= _groupCount; i++) {
        if (match.group(i) != null) {
          matchedStyle = _getStyleForGroup(i);
          break;
        }
      }

      children.add(TextSpan(text: match.group(0), style: matchedStyle ?? style));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < textContent.length) {
      children.add(TextSpan(text: textContent.substring(lastMatchEnd), style: style));
    }

    _lastText = textContent;
    _lastLanguage = language;
    _cachedTextSpan = TextSpan(style: style, children: children);
    return _cachedTextSpan!;
  }

  // ── 8 token groups ─────────────────────────────────────────────────────────
  // IMPORTANT: use non-capturing (?:...) inside each group so that
  // match.group(N) == the WHOLE token and group numbers stay stable.
  // Group 1  → comment
  // Group 2  → string  (double-quoted, single-quoted, triple-quoted)
  // Group 3  → keyword
  // Group 4  → builtin/type
  // Group 5  → function call  (name followed by '(')
  // Group 6  → number
  // Group 7  → bracket
  // Group 8  → operator

  static const int _groupCount = 9;

  RegExp _getPatterns(String lang) {
    // Each pattern here should NOT have capturing parentheses.
    // They will be wrapped in exactly one set of () in the final RegExp.
    
    // 1. comment
    const comment = r'//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*';
    // 2. string
    const string = r'"""[\s\S]*?"""|' + "'''[\\s\\S]*?'''|" + r'"(?:[^"\\]|\\.)*"|' + r"'(?:[^'\\]|\\.)*'";
    // 3. keyword (already uses non-capturing groups internally)
    final keyword = _keywords(lang);
    // 4. builtin/type
    final builtin = _builtins(lang);
    // 5. function call
    const function = r'\b[a-zA-Z_]\w*(?=\s*\()';
    // 6. number
    const number = r'\b(?:0x[\da-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?)\b';
    // 7. bracket
    const bracket = r'[{}()\[\]]';
    // 8. operator
    const operator = r'->|::|=>|[+\-*/%&|^~<>!]=?|[=,;:]';
    // 9. variable / special identifier
    const variable = r'\b(?:this|self|cls|arguments|super|proto)\b';

    return RegExp(
      '($comment)|($string)|($keyword)|($builtin)|($function)|($number)|($bracket)|($operator)|($variable)',
      multiLine: true,
    );
  }

  TextStyle? _getStyleForGroup(int group) {
    switch (group) {
      case 1: return styles['comment'];
      case 2: return styles['string'];
      case 3: return styles['keyword'];
      case 4: return styles['type'];
      case 5: return styles['function'];
      case 6: return styles['number'];
      case 7: return styles['bracket'];
      case 8: return styles['operator'];
      case 9: return styles['variable'];
      default: return null;
    }
  }

  // ── Language-specific keyword lists ────────────────────────────────────────

  String _keywords(String lang) {
    switch (lang) {
      case 'py':
        return r'\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b';
      case 'js':
      case 'ts':
        return r'\b(?:async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|false|finally|for|from|function|if|import|in|instanceof|let|new|null|of|return|static|super|switch|this|throw|true|try|typeof|undefined|var|void|while|with|yield)\b';
      case 'java':
        return r'\b(?:abstract|assert|boolean|break|byte|case|catch|char|class|const|continue|default|do|double|else|enum|extends|final|finally|float|for|goto|if|implements|import|instanceof|int|interface|long|native|new|null|package|private|protected|public|return|short|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while|true|false)\b';
      default: // c, cpp
        return r'\b(?:alignas|alignof|and|and_eq|asm|auto|bitand|bitor|bool|break|case|catch|char|char16_t|char32_t|class|compl|const|constexpr|const_cast|continue|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|final|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|not_eq|nullptr|operator|or|or_eq|override|private|protected|public|register|reinterpret_cast|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|thread_local|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while|xor|xor_eq)\b';
    }
  }

  String _builtins(String lang) {
    switch (lang) {
      case 'py':
        return r'\b(?:abs|all|any|ascii|bin|bool|breakpoint|bytearray|bytes|callable|chr|compile|complex|delattr|dict|dir|divmod|enumerate|eval|exec|filter|float|format|frozenset|getattr|globals|hasattr|hash|help|hex|id|input|int|isinstance|issubclass|iter|len|list|locals|map|max|memoryview|min|next|object|oct|open|ord|pow|print|property|range|repr|reversed|round|set|setattr|slice|sorted|staticmethod|str|sum|super|tuple|type|vars|zip)\b';
      case 'js':
      case 'ts':
        return r'\b(?:Array|Boolean|console|Date|document|Error|Function|JSON|Map|Math|NaN|Number|Object|Promise|Proxy|Reflect|RegExp|Set|String|Symbol|WeakMap|WeakSet|Window|alert|confirm|fetch|isFinite|isNaN|parseInt|parseFloat|prompt|require|setTimeout|clearTimeout|setInterval|clearInterval|window)\b';
      case 'java':
        return r'\b(?:String|System|Math|Object|Integer|Double|Boolean|Character|Long|Float|Short|Byte|ArrayList|HashMap|List|Map|Set|Iterator|Scanner|Arrays|Collections|StringBuilder|StringBuffer|Thread|Exception|RuntimeException|IllegalArgumentException|NullPointerException|IOException)\b';
      default: // c, cpp
        return r'\b(?:printf|scanf|fprintf|fscanf|sprintf|sscanf|malloc|free|calloc|realloc|exit|abort|abs|sqrt|pow|sin|cos|tan|log|exp|memset|memcpy|memmove|strcpy|strncpy|strcat|strncat|strcmp|strncmp|strlen|auto|bool|char|double|float|int|long|short|signed|size_t|ssize_t|string|unsigned|void|wchar_t|int8_t|int16_t|int32_t|int64_t|uint8_t|uint16_t|uint32_t|uint64_t|std|vector|map|set|list|pair|queue|stack|array|deque|unordered_map|unordered_set|shared_ptr|unique_ptr|weak_ptr|nullptr_t|ptrdiff_t)\b';
    }
  }
}

class CodeStyles {
  static Map<String, TextStyle> dark() => {
    'comment': const TextStyle(color: Color(0xFF5C6370), fontStyle: FontStyle.italic),
    'string': const TextStyle(color: Color(0xFF98C379)),
    'keyword': const TextStyle(color: Color(0xFFC678DD)),
    'type': const TextStyle(color: Color(0xFFE5C07B)),
    'function': const TextStyle(color: Color(0xFF61AFEF)),
    'number': const TextStyle(color: Color(0xFFD19A66)),
    'bracket': const TextStyle(color: Color(0xFFABB2BF)),
    'operator': const TextStyle(color: Color(0xFF56B6C2)),
    'variable': const TextStyle(color: Color(0xFFE06C75)),
  };

  static Map<String, TextStyle> light() => {
    'comment': const TextStyle(color: Color(0xFFA0A1A7), fontStyle: FontStyle.italic),
    'string': const TextStyle(color: Color(0xFF50A14F)),
    'keyword': const TextStyle(color: Color(0xFFA626A4)),
    'type': const TextStyle(color: Color(0xFF986801)),
    'function': const TextStyle(color: Color(0xFF4078F2)),
    'number': const TextStyle(color: Color(0xFF986801)),
    'bracket': const TextStyle(color: Color(0xFF383A42)),
    'operator': const TextStyle(color: Color(0xFF0184BC)),
    'variable': const TextStyle(color: Color(0xFFE45649)),
  };
}
