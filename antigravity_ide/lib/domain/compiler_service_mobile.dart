import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'compiler_service_base.dart';
import 'terminal_controller.dart';

class CompilerService implements CompilerServiceBase {
  static const MethodChannel _pythonLocalChannel =
      MethodChannel('locode/python_local');
  final _outputController = StreamController<String>.broadcast();
  final _runningController = StreamController<bool>.broadcast();
  late final WebViewController _controller;
  WebViewController get webViewController => _controller;
  HttpServer? _server;
  
  TerminalController? _terminalController;
  void setTerminalController(TerminalController controller) {
    _terminalController = controller;
  }

  String _currentOutput = '';
  int _runId = 0;
  bool _engineReady = false;
  bool _pythonReady = false;
  int? _port;
  Timer? _runTimer;
  Timer? _firstResponseTimer;
  Timer? _dispatchAckTimer;
  Timer? _diagTicker;
  Timer? _engineTimer;
  bool _retriedWithLocalhost = false;
  bool _gotResponseForActiveRun = false;
  bool _gotDispatchAck = false;
  bool _isRunning = false;
  String _activeExt = '';
  bool _isPythonOnline = false;

  String _normalizeExt(String ext) {
    var e = ext.trim().toLowerCase();
    if (e.startsWith('.')) e = e.substring(1);
    if (e == 'python') return 'py';
    if (e == 'c++') return 'cpp';
    return e;
  }

  @override
  Stream<String> get outputStream => _outputController.stream;

  @override
  Stream<bool> get runningStream => _runningController.stream;

  @override
  void init() {
    _outputController.add(
      "Initializing local compiler engine...\n"
      "[BUILD_MARKER] MOBILE_PIPELINE_V3_2026_04_21\n",
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'CompilerChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            final type = (data['type'] ?? '').toString();
            if (type == 'engine_ready' || type == 'system') {
              _engineReady = true;
              _engineTimer?.cancel();
              _currentOutput = "Compiler engine ready.\n";
              _outputController.add(_currentOutput);
              return;
            }
            if (type == 'ready') {
              if ((data['ext'] ?? '').toString() == 'py') {
                _pythonReady = true;
              }
              return;
            }
            if (type == 'python_ready') {
              _pythonReady = true;
              return;
            }
            final isRunMessage = type == 'dispatch_ack' || type == 'stdout' || type == 'stderr' || type == 'run_error' || type == 'run_done' || type == 'done';
            if (isRunMessage && !_isRunning) return;

            if (type == 'dispatch_ack') {
              _gotDispatchAck = true;
              _dispatchAckTimer?.cancel();
              return;
            }

            if (type == 'stdout' || type == 'stderr' || type == 'run_error') {
              final raw = data['data']?.toString() ?? '';
              if (raw.isNotEmpty) {
                _gotResponseForActiveRun = true;
                _firstResponseTimer?.cancel();
                _currentOutput += raw;
                _outputController.add(raw);
              }
            } else if (type == 'run_done' || type == 'done') {
              _gotResponseForActiveRun = true;
              _firstResponseTimer?.cancel();
              _runTimer?.cancel();
              _dispatchAckTimer?.cancel();
              _diagTicker?.cancel();
              _isRunning = false;
              _runningController.add(false);
            }
          } catch (e) {
            _outputController.add(
              "$_currentOutput\n[Engine Error] Invalid message: $e\n",
            );
          }
        },
      )
      ..setOnConsoleMessage((message) {
        if (message.level == JavaScriptLogLevel.error) {
          _outputController.add(
            "$_currentOutput\n[Engine Console Error] ${message.message}\n",
          );
        }
      });

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (WebResourceError error) {
          _outputController.add(
            "$_currentOutput\n[Engine Fatal] Failed to load Python engine (${error.errorCode}: ${error.description}).\n",
          );
        },
      ),
    );

    _startLocalServer();
  }

  Future<void> _startLocalServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      _server!.listen((HttpRequest request) async {
        final path = request.uri.path;
        String assetPath = path;
        if (assetPath == '/') assetPath = '/assets/compile_engine.html';
        if (assetPath.startsWith('/')) assetPath = assetPath.substring(1);

        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.set('Access-Control-Allow-Headers', '*');
        request.response.headers.set('Access-Control-Allow-Private-Network', 'true');
        request.response.headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
        request.response.headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
        request.response.headers.set('Cross-Origin-Opener-Policy', 'same-origin');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = 204;
          await request.response.close();
          return;
        }

        if (path == '/stdin') {
          // This is the "Blocking Read" endpoint for workers.
          // It will stay open until input is available.
          if (_terminalController != null) {
            while (_isRunning && !_terminalController!.hasPendingSubmit) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
            
            final input = _terminalController!.getAndClearPending();
            request.response.headers.contentType = ContentType.text;
            request.response.write(input);
          } else {
            request.response.write('');
          }
          await request.response.close();
          return;
        }

        try {
          final assetPathResolved = path == '/' ? 'assets/compile_engine.html' : (path.startsWith('/') ? path.substring(1) : path);
          final byteData = await rootBundle.load(assetPathResolved);
          final bytes = byteData.buffer.asUint8List();

          if (assetPathResolved.endsWith('.html')) {
            request.response.headers.contentType = ContentType.html;
          } else if (assetPathResolved.endsWith('.js')) {
            request.response.headers.contentType = ContentType('application', 'javascript', charset: 'utf-8');
          } else if (assetPathResolved.endsWith('.wasm')) {
            request.response.headers.contentType = ContentType('application', 'wasm');
          } else if (assetPathResolved.endsWith('.json')) {
            request.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
          } else if (assetPathResolved.endsWith('.zip')) {
            request.response.headers.contentType = ContentType('application', 'zip');
          } else if (assetPathResolved.endsWith('.data')) {
            request.response.headers.contentType = ContentType('application', 'octet-stream');
          } else {
            request.response.headers.contentType = ContentType('application', 'octet-stream');
          }

          request.response.add(bytes);
        } catch (e) {
          request.response.statusCode = 404;
        } finally {
          await request.response.close();
        }
      });

      _loadEngine(useLocalhost: false);
      _armEngineTimeout();
    } catch (e) {
      _outputController.add(
        "$_currentOutput\n[Engine Fatal] Failed to start Python engine server: $e\n",
      );
    }
  }

  @override
  void runCode(String code, String ext, {String stdin = ''}) {
    final normalizedExt = _normalizeExt(ext);
    // Detour for local Python execution removed to enable interactive stdin via web-engine
    /*
    if (normalizedExt == 'py') {
      _runPythonLocally(code);
      return;
    }
    */

    if (normalizedExt != 'c' && normalizedExt != 'cpp' && normalizedExt != 'py') {
      _outputController.add(
        "Unsupported extension .$normalizedExt in mobile mode.\n"
        "Use .py, .c or .cpp.\n",
      );
      _runningController.add(false);
      return;
    }

    if (!_engineReady) {
      _outputController.add("Engine not ready yet. Please wait a moment and retry.\n");
      return;
    }

    _runId++;
    final thisRun = _runId;
    _activeExt = normalizedExt;
    _currentOutput = '';
    _gotResponseForActiveRun = false;
    _isRunning = true;
    _runningController.add(true);
    _runTimer?.cancel();
    
    _outputController.add(_currentOutput);

    final safeCode = jsonEncode(code);
    final safeStdin = jsonEncode(stdin);
    final safeExt = jsonEncode(normalizedExt);
    final isOnline = _activeExt == 'py' && _isPythonOnline;
    _armRunTimeout(thisRun);
    _controller
        .runJavaScript(
          """
          (function() {
            try {
              if (typeof runCode !== 'function') {
                if (window.CompilerChannel && typeof window.CompilerChannel.postMessage === 'function') {
                  window.CompilerChannel.postMessage(JSON.stringify({
                    type: 'stderr',
                    data: 'runCode() missing in compile engine page\\n',
                    runId: $thisRun
                  }));
                  window.CompilerChannel.postMessage(JSON.stringify({
                    type: 'done',
                    data: '',
                    runId: $thisRun
                  }));
                }
                return;
              }
              runCode($safeExt, $safeCode, $thisRun, $safeStdin, $isOnline);
            } catch (e) {
              if (window.CompilerChannel && typeof window.CompilerChannel.postMessage === 'function') {
                window.CompilerChannel.postMessage(JSON.stringify({
                  type: 'stderr',
                  data: 'Dispatch exception: ' + String(e) + '\\n',
                  runId: $thisRun
                }));
                window.CompilerChannel.postMessage(JSON.stringify({
                  type: 'done',
                  data: '',
                  runId: $thisRun
                }));
              }
            }
          })();
          """,
        )
        .catchError((error) {
      if (!_isRunning) return;
      _runTimer?.cancel();
      _currentOutput +=
          "\n[Engine Error] Failed to dispatch .$normalizedExt execution: $error\n";
      _outputController.add(_currentOutput);
      _isRunning = false;
      _runningController.add(false);
    });
  }

  void _runPythonLocally(String code) {
    _runId++;
    _currentOutput = "[Local Python] Running on-device runtime...\n";
    _outputController.add(_currentOutput);
    _runningController.add(true);

    _pythonLocalChannel.invokeMethod<Map<dynamic, dynamic>>(
      'runPython',
      <String, dynamic>{'code': code, 'timeoutMs': 10000},
    ).then((result) {
      final stdout = (result?['stdout'] ?? '').toString();
      final stderr = (result?['stderr'] ?? '').toString();
      final ok = result?['ok'] == true;

      _currentOutput = '';
      if (stdout.isNotEmpty) {
        _currentOutput += stdout.endsWith('\n') ? stdout : '$stdout\n';
      }
      if (stderr.isNotEmpty) {
        _currentOutput += stderr.endsWith('\n') ? stderr : '$stderr\n';
      }
      if (!ok && _currentOutput.isEmpty) {
        _currentOutput = 'Python execution failed.\n';
      }
      if (_currentOutput.isEmpty) {
        _currentOutput = 'Execution finished with no stdout/stderr.\n';
      }
      _outputController.add(_currentOutput);
      _runningController.add(false);
    }).catchError((error) {
      _currentOutput = 'Python execution bridge error: $error\n';
      _outputController.add(_currentOutput);
      _runningController.add(false);
    });
  }

  @override
  void stopExecution(String ext) {
    final normalizedExt = _normalizeExt(ext);
    /*
    if (normalizedExt == 'py') {
      _pythonLocalChannel.invokeMethod('stopPython');
      _runningController.add(false);
      return;
    }
    */
    if (!_engineReady) return;
    _runId++;
    _runTimer?.cancel();
    _firstResponseTimer?.cancel();
    _dispatchAckTimer?.cancel();
    _diagTicker?.cancel();
    _isRunning = false;
    _runningController.add(false);
    final safeExt = jsonEncode(normalizedExt);
    _controller.runJavaScript("stopCode($safeExt)");
  }

  @override
  void sendStdin(String data, String ext) {
    final normalizedExt = _normalizeExt(ext);
    /*
    if (normalizedExt == 'py') {
      _pythonLocalChannel.invokeMethod('sendStdin', {'data': data});
      return;
    }
    */
    if (!_engineReady) return;
    final safeExt = jsonEncode(normalizedExt);
    final safeData = jsonEncode(data);
    _controller.runJavaScript("writeStdin($safeExt, $safeData)");
  }

  @override
  void setPythonOnline(bool online) {
    _isPythonOnline = online;
    // We can also signal the engine to preload Pyodide if needed, 
    // but runCode will handle it lazily.
  }

  void _armFirstResponseTimeout(int runId) {
    _firstResponseTimer = Timer(const Duration(seconds: 3), () {
      if (!_isRunning || _gotResponseForActiveRun) return;
      _currentOutput +=
          "\n[Bridge Error] Python engine did not respond after dispatch.\n"
          "Reloading Python worker and stopping this run.\n";
      _outputController.add(_currentOutput);
      _diagTicker?.cancel();
      _isRunning = false;
      _runningController.add(false);
      _runId++;
      _controller.runJavaScript("stopPython()");
    });
  }

  void _armDispatchAckTimeout(int runId, String safeCode) {
    _dispatchAckTimer = Timer(const Duration(seconds: 2), () {
      if (!_isRunning || _gotDispatchAck) return;
      _currentOutput +=
          "\n[Bridge Error] No dispatch ACK from Python engine.\n"
          "Reloading engine and retrying once...\n";
      _outputController.add(_currentOutput);
      _loadEngine(useLocalhost: _retriedWithLocalhost);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!_isRunning || _gotDispatchAck) return;
        _controller.runJavaScript(
          """
          (function() {
            try {
              if (typeof executePython === 'function') {
                setTimeout(function() {
                  executePython($safeCode, $runId);
                }, 0);
              } else if (window.CompilerChannel && typeof window.CompilerChannel.postMessage === 'function') {
                window.CompilerChannel.postMessage(JSON.stringify({
                  type: 'run_error',
                  data: 'executePython() still missing after reload\\n',
                  runId: $runId
                }));
                window.CompilerChannel.postMessage(JSON.stringify({
                  type: 'run_done',
                  data: '',
                  runId: $runId
                }));
              }
            } catch (e) {
              if (window.CompilerChannel && typeof window.CompilerChannel.postMessage === 'function') {
                window.CompilerChannel.postMessage(JSON.stringify({
                  type: 'run_error',
                  data: 'Retry dispatch exception: ' + String(e) + '\\n',
                  runId: $runId
                }));
                window.CompilerChannel.postMessage(JSON.stringify({
                  type: 'run_done',
                  data: '',
                  runId: $runId
                }));
              }
            }
          })();
          """,
        );
        // Absolute failsafe: never remain running forever.
        Future.delayed(const Duration(seconds: 4), () {
          if (!_isRunning || _gotResponseForActiveRun) return;
          _currentOutput +=
              "\n[Hard Failsafe] Python bridge remained unresponsive.\n"
              "Execution force-stopped to prevent infinite Running state.\n";
          _outputController.add(_currentOutput);
          _diagTicker?.cancel();
          _isRunning = false;
          _runningController.add(false);
          _controller.runJavaScript("stopPython()");
        });
      });
    });
  }

  void _armDiagTicker(int runId) {
    // Debug diagnostics removed
  }

  void _armRunTimeout(int runId) {
    _runTimer = Timer(const Duration(seconds: 300), () {
      if (runId != _runId) return;
      _currentOutput +=
          "\n[Timeout] Execution stalled for .$_activeExt. Worker restarted.\n";
      _outputController.add(_currentOutput);
      _runningController.add(false);
      _runId++;
      final safeExt = jsonEncode(_activeExt);
      _controller.runJavaScript("stopCode($safeExt)");
    });
  }

  void _loadEngine({required bool useLocalhost}) {
    if (_port == null) return;
    final host = useLocalhost ? 'localhost' : '127.0.0.1';
    final cacheBust = DateTime.now().microsecondsSinceEpoch;
    _controller.loadRequest(
      Uri.parse(
        'http://$host:${_port!}/assets/compile_engine.html?v=$cacheBust',
      ),
    );
  }

  void _armEngineTimeout() {
    _engineTimer?.cancel();
    _engineTimer = Timer(const Duration(seconds: 8), () {
      if (_engineReady) return;
      if (!_retriedWithLocalhost) {
        _retriedWithLocalhost = true;
        _outputController.add(
          "$_currentOutput\n[Engine] Retry with localhost fallback...\n",
        );
        _loadEngine(useLocalhost: true);
        _armEngineTimeout();
        return;
      }
      _outputController.add(
        "$_currentOutput\n[Engine Fatal] Python engine failed to initialize.\n",
      );
    });
  }
}

final compilerService = CompilerService();
