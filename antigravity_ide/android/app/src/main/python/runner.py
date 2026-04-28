import io
import traceback
from contextlib import redirect_stdout, redirect_stderr


def _unsupported_input(prompt=""):
    raise EOFError(
        "input() is not supported in local mobile Python runtime yet. "
        "Use hardcoded test values instead."
    )


def run_code(code: str):
    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    ok = True
    try:
        with redirect_stdout(stdout_buffer), redirect_stderr(stderr_buffer):
            scope = {
                "__name__": "__main__",
                "input": _unsupported_input,
            }
            exec(code, scope, scope)
    except Exception:
        ok = False
        stderr_buffer.write(traceback.format_exc())

    return {
        "ok": ok,
        "stdout": stdout_buffer.getvalue(),
        "stderr": stderr_buffer.getvalue(),
    }
