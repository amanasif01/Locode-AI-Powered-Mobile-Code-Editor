import 'dart:convert';
import 'dart:async';
import 'package:universal_html/html.dart' as html;
import 'compiler_service_base.dart';

/// Web implementation of the compiler service.
/// Workers communicate by postMessage-ing JSON *strings* (not JS objects),
/// so this service only needs dart:convert — no dart:js_util required.
class CompilerService implements CompilerServiceBase {
  late html.Worker _pyWorker;
  late html.Worker _jsWorker;
  late html.Worker _cppWorker;
  late html.Worker _javaWorker;
  late html.Worker _cWorker;

  final _outputController = StreamController<String>.broadcast();
  @override
  Stream<String> get outputStream => _outputController.stream;

  final _runningController = StreamController<bool>.broadcast();
  @override
  Stream<bool> get runningStream => _runningController.stream;

  String _currentOutput = '';
  int _sessionId = 0;
  bool _isPythonOnline = false;

  @override
  void init() {
    _pyWorker  = _bindWorker('pyodide_worker.js');
    _jsWorker  = _bindWorker('js_worker.js');
    _cppWorker = _bindWorker('cpp_worker.js');
    _javaWorker = _bindWorker('java_worker.js');
    _cWorker   = _bindWorker('c_worker.js');
  }

  html.Worker _bindWorker(String path) {
    final worker = html.Worker(path);
    worker.onMessage.listen((event) {
      if (event.data == null) return;
      try {
        // Workers send JSON strings — parse with standard dart:convert
        final Map<String, dynamic> data = jsonDecode(event.data.toString());
        final String type = data['type'] ?? '';
        final int msgSession = (data['session'] ?? -1) as int;

        // Discard messages from a stale execution session
        if (msgSession != _sessionId && msgSession != -1) return;

        if (type == 'done') {
          if (msgSession == _sessionId || msgSession == -1) {
            _runningController.add(false);
          }
          return;
        }

        if (type == 'ready') return; // Pyodide ready signal — no action needed on web

        if (type == 'stdout' || type == 'stderr') {
          final String msgData = (data['data'] ?? '').toString();
          if (msgData.isNotEmpty) {
            _currentOutput += msgData;
            _outputController.add(msgData);
          }
        }
      } catch (e) {
        // ignore parse errors from non-JSON messages
      }
    });
    return worker;
  }

  @override
  void runCode(String code, String ext, {String stdin = ''}) {
    _sessionId++;
    _currentOutput = '';
    _runningController.add(true);

    // Send as JSON string so the worker can parse it without js_util on either end
    final payload = jsonEncode({
      'code': code, 
      'stdin': stdin, 
      'session': _sessionId,
      'online': ext == 'py' && _isPythonOnline,
    });

    switch (ext) {
      case 'py':   _pyWorker.postMessage(payload);   break;
      case 'js':   _jsWorker.postMessage(payload);   break;
      case 'cpp':  _cppWorker.postMessage(payload);  break;
      case 'java': _javaWorker.postMessage(payload); break;
      case 'c':    _cWorker.postMessage(payload);    break;
      default:
        _outputController.add('Error: Unrecognized language extension .$ext\n');
        _runningController.add(false);
    }
  }

  @override
  void stopExecution(String ext) {
    _sessionId++;
    _runningController.add(false);
    _outputController.add('$_currentOutput\n⏹  Execution stopped by user.');
    switch (ext) {
      case 'py':
        _pyWorker.terminate();
        _pyWorker = _bindWorker('pyodide_worker.js');
        break;
      case 'js':
        _jsWorker.terminate();
        _jsWorker = _bindWorker('js_worker.js');
        break;
      case 'cpp':
        _cppWorker.terminate();
        _cppWorker = _bindWorker('cpp_worker.js');
        break;
      case 'java':
        _javaWorker.terminate();
        _javaWorker = _bindWorker('java_worker.js');
        break;
      case 'c':
        _cWorker.terminate();
        _cWorker = _bindWorker('c_worker.js');
        break;
    }
  }

  @override
  void sendStdin(String data, String ext) {
    // Forward to appropriate worker
    final payload = jsonEncode({'type': 'stdin', 'data': data});
    switch (ext) {
      case 'py': _pyWorker.postMessage(payload); break;
      case 'js': _jsWorker.postMessage(payload); break;
    }
  }

  @override
  void setPythonOnline(bool online) {
    _isPythonOnline = online;
  }
}

final compilerService = CompilerService();
