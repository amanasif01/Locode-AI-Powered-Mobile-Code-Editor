import 'dart:async';

abstract class CompilerServiceBase {
  Stream<String> get outputStream;
  Stream<bool> get runningStream;
  
  void init();
  void runCode(String code, String ext, {String stdin = ''});
  void stopExecution(String ext);
  void sendStdin(String data, String ext);
  void setPythonOnline(bool online);
}
