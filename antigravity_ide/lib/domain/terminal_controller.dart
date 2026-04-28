import 'dart:async';
import 'package:flutter/material.dart';

class TerminalLine {
  final String text;
  final Color? color;
  final bool isInput;

  TerminalLine(this.text, {this.color, this.isInput = false});
}

class TerminalController extends ChangeNotifier {
  final List<TerminalLine> _lines = [];
  String _currentInput = '';
  final List<String> _history = [];
  int _historyIndex = -1;
  
  bool _isFocused = false;
  bool get isFocused => _isFocused;
  set isFocused(bool value) {
    _isFocused = value;
    notifyListeners();
  }

  List<TerminalLine> get lines => List.unmodifiable(_lines);
  String get currentInput => _currentInput;

  bool _lastLineFinished = true;

  void addOutput(String text, {Color? color}) {
    if (text.isEmpty) return;
    
    final parts = text.split('\n');
    final bool endsWithNewline = text.endsWith('\n');

    for (var i = 0; i < parts.length; i++) {
      String part = parts[i];
      if (i == parts.length - 1 && part.isEmpty && endsWithNewline) {
        _lastLineFinished = true;
        break;
      }

      if (!_lastLineFinished && _lines.isNotEmpty) {
        // Append to last line
        final last = _lines.removeLast();
        _lines.add(TerminalLine(last.text + part, color: color ?? last.color, isInput: last.isInput));
      } else {
        _lines.add(TerminalLine(part, color: color, isInput: false));
      }
      
      if (i < parts.length - 1) {
        _lastLineFinished = true;
      } else {
        _lastLineFinished = endsWithNewline;
      }
    }

    if (_lines.length > 1000) _lines.removeRange(0, _lines.length - 1000);
    notifyListeners();
  }

  void addInputChar(String char) {
    _currentInput += char;
    notifyListeners();
  }

  void setInput(String value) {
    _currentInput = value;
    notifyListeners();
  }

  void backspace() {
    if (_currentInput.isNotEmpty) {
      _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      notifyListeners();
    }
  }

  String _pendingInput = '';
  bool _hasPendingSubmit = false;
  bool get hasPendingSubmit => _hasPendingSubmit;

  String submit() {
    final input = _currentInput;
    _lines.add(TerminalLine('➜ $input', color: const Color(0xFF00FF88), isInput: true));
    if (input.trim().isNotEmpty) {
      _history.add(input);
      if (_history.length > 50) _history.removeAt(0);
    }
    _pendingInput = '$input\n';
    _hasPendingSubmit = true;
    _currentInput = '';
    _historyIndex = -1;
    _lastLineFinished = true;
    notifyListeners();
    return input;
  }

  String getAndClearPending() {
    _hasPendingSubmit = false;
    final res = _pendingInput;
    _pendingInput = '';
    return res;
  }

  void historyUp() {
    if (_history.isEmpty) return;
    if (_historyIndex == -1) {
      _historyIndex = _history.length - 1;
    } else if (_historyIndex > 0) {
      _historyIndex--;
    }
    _currentInput = _history[_historyIndex];
    notifyListeners();
  }

  void historyDown() {
    if (_historyIndex == -1) return;
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _currentInput = _history[_historyIndex];
    } else {
      _historyIndex = -1;
      _currentInput = '';
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _currentInput = '';
    notifyListeners();
  }
}
