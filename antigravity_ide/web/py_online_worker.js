// Pyodide Online Worker — Full Python Runtime from CDN
// Uses the same message contract and synchronous stdin bridge as the Light worker.
importScripts("https://cdn.jsdelivr.net/pyodide/v0.26.1/full/pyodide.js");

let pyodide = null;
let _currentSession = -1;

function jsonMsg(type, data, session) {
    return JSON.stringify({ type, data, session });
}

async function init() {
    self.postMessage(jsonMsg('stdout', '⌛ Initializing Python Online (Pyodide)...\n', -1));
    try {
        pyodide = await loadPyodide();
        
        // Expose unbuffered stdout/stderr direct to JS
        self.pyodide_stdout = (str) => {
            self.postMessage(jsonMsg('stdout', str, _currentSession));
        };
        self.pyodide_stderr = (str) => {
            self.postMessage(jsonMsg('stderr', str, _currentSession));
        };

        // Inject unbuffered JS handlers into Python
        await pyodide.runPythonAsync(`
import sys
import js
class JsStdout:
    def write(self, data):
        js.pyodide_stdout(data)
        return len(data)
    def flush(self):
        pass
class JsStderr:
    def write(self, data):
        js.pyodide_stderr(data)
        return len(data)
    def flush(self):
        pass
sys.stdout = JsStdout()
sys.stderr = JsStderr()
        `);

        self.postMessage(jsonMsg('stdout', '✅ Python Online Ready (Pyodide)\n', -1));
        self.postMessage(jsonMsg('ready', '', -1));
    } catch (err) {
        self.postMessage(jsonMsg('stderr', 'Failed to load Pyodide: ' + err + '\n', -1));
    }
}

init();

self.onmessage = async (event) => {
    let payload = event.data;
    if (typeof payload === 'string') {
        try { payload = JSON.parse(payload); } catch(e) { payload = {}; }
    }

    if (payload.type === 'stdin') {
        // We don't use this for Pyodide worker because we use the Sync XHR bridge.
        return;
    }

    const code = payload.code || '';
    const session = payload.session !== undefined ? payload.session : -1;
    _currentSession = session;

    if (!pyodide) {
        self.postMessage(jsonMsg('stderr', 'Python Online is still loading...\n', session));
        self.postMessage(jsonMsg('done', '', session));
        return;
    }

    // Configure stdout/stderr no-ops (using sys.stdout override)
    pyodide.setStdout({ batched: (str) => {} });
    pyodide.setStderr({ batched: (str) => {} });

    // Configure synchronous stdin bridge
    pyodide.setStdin({
        stdin: () => {
            // Signal Flutter that we are waiting for input (to keep terminal active)
            self.postMessage(jsonMsg('input_request', '', session));
            
            // Perform a SYNCHRONOUS XHR to the blocking /stdin endpoint.
            // This is ONLY allowed in a Worker thread.
            const xhr = new XMLHttpRequest();
            // Use relative path; the server will handle it.
            xhr.open('GET', '/stdin?session=' + session + '&cache=' + Date.now(), false);
            xhr.send();
            
            if (xhr.status === 200) {
                return xhr.responseText;
            } else {
                return "";
            }
        }
    });

    try {
        await pyodide.runPythonAsync(code);
        self.postMessage(jsonMsg('done', '', session));
    } catch (err) {
        self.postMessage(jsonMsg('stderr', err.toString() + '\n', session));
        self.postMessage(jsonMsg('done', '', session));
    }
};
