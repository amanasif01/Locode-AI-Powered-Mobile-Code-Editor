package com.example.antigravity_ide

import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.chaquo.python.PyObject
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

class MainActivity : FlutterActivity() {
    private val pythonChannelName = "locode/python_local"
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile
    private var runningTask: Future<*>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pythonChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "runPython" -> {
                        val code = call.argument<String>("code") ?: ""
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000
                        try {
                            val task = executor.submit(Callable<Map<String, Any>> {
                                val py = Python.getInstance()
                                val module = py.getModule("runner")
                                val out: PyObject = module.callAttr("run_code", code)
                                val okValue = try {
                                    out.callAttr("__getitem__", "ok").toJava(Boolean::class.java) ?: false
                                } catch (_: Exception) {
                                    false
                                }
                                val stdoutValue = try {
                                    out.callAttr("__getitem__", "stdout").toJava(String::class.java) ?: ""
                                } catch (_: Exception) {
                                    ""
                                }
                                val stderrValue = try {
                                    out.callAttr("__getitem__", "stderr").toJava(String::class.java) ?: ""
                                } catch (_: Exception) {
                                    ""
                                }
                                mapOf(
                                    "ok" to okValue,
                                    "stdout" to stdoutValue,
                                    "stderr" to stderrValue
                                )
                            })
                            runningTask = task
                            val data = task.get(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
                            runningTask = null
                            result.success(data)
                        } catch (_: TimeoutException) {
                            runningTask?.cancel(true)
                            runningTask = null
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "stdout" to "",
                                    "stderr" to "Execution timed out.\n"
                                )
                            )
                        } catch (e: Exception) {
                            runningTask = null
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "stdout" to "",
                                    "stderr" to ("Python execution failed: ${e.message}\n${e.stackTraceToString()}\n")
                                )
                            )
                        }
                    }
                    "stopPython" -> {
                        runningTask?.cancel(true)
                        runningTask = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
