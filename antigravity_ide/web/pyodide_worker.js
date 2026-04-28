// Lightweight offline Python worker using Skulpt (pure JS runtime).
// Keeps message contract unchanged so mobile/web compiler services
// do not need to change.
importScripts("skulpt/skulpt.min.js", "skulpt/skulpt-stdlib.js");

let skulptReady = false;

function parsePayload(data) {
    if (typeof data === 'string') {
        try { return JSON.parse(data); } catch(e) { return {}; }
    }
    return data || {};
}

function jsonMsg(type, data, session) {
    return JSON.stringify({ type, data, session });
}

// ── Interactive stdin bridge ─────────────────────────────────────────────────
// Skulpt's asyncToPromise expects inputfun to return a Promise.
// Sync XHR inside a Promise chain freezes Skulpt's execution loop.
// Instead: store the resolve function, post an input_request to the main
// thread, and resolve when onmessage receives a { type:'stdin' } message.

let _pendingInputResolve = null;
let _currentSession = -1;

function skulptInputFun(prompt) {
    // Post the prompt immediately so it appears before blocking.
    if (prompt) {
        self.postMessage(jsonMsg('stdout', String(prompt), _currentSession));
    }
    // Return a Promise that resolves when the user submits a line.
    return new Promise((resolve) => {
        _pendingInputResolve = resolve;
        // Signal the main thread that we are waiting for input.
        self.postMessage(jsonMsg('input_request', '', _currentSession));
    });
}

async function load() {
    self.postMessage(jsonMsg('stdout', '⌛ Initializing lightweight Python runtime...\n', -1));
    try {
        if (typeof self.Sk === "undefined") {
            throw new Error("Skulpt runtime not found");
        }
        skulptReady = true;
        self.postMessage(jsonMsg('ready', '', -1));
        self.postMessage(jsonMsg('stdout', '✅ Python Engine Ready (Skulpt)\n', -1));
    } catch (err) {
        let errorMsg = 'Failed to initialize Skulpt: ' + (err.message || String(err));
        console.error(errorMsg, err);
        self.postMessage(jsonMsg('stderr', errorMsg + '\n', -1));
        self.postMessage(jsonMsg('init_failed', errorMsg, -1));
    }
}

load();

self.onmessage = async (event) => {
    const payload = parsePayload(event.data);

    // Route stdin data to any pending Python input() call.
    if (payload.type === 'stdin') {
        if (_pendingInputResolve) {
            const raw = String(payload.data || '');
            // Strip trailing newline — Python input() does not include it.
            const line = raw.endsWith('\n') ? raw.slice(0, -1) : raw;
            const resolve = _pendingInputResolve;
            _pendingInputResolve = null;
            resolve(line);
        }
        return;
    }

    const code = payload.code || '';
    const session = payload.session !== undefined ? payload.session : -1;
    _currentSession = session;

    if (!skulptReady) {
        self.postMessage(jsonMsg('stderr', 'Python engine is still initializing. Please wait a moment and try again.\n', session));
        self.postMessage(jsonMsg('done', '', session));
        return;
    }

    let stdoutBuf = '';
    let stderrBuf = '';

    const flushOutputs = () => {
        if (stdoutBuf) {
            self.postMessage(jsonMsg('stdout', stdoutBuf, session));
            stdoutBuf = '';
        }
        if (stderrBuf) {
            self.postMessage(jsonMsg('stderr', stderrBuf, session));
            stderrBuf = '';
        }
    };

    try {
        self.Sk.pre = "output";
        // Remove execution time limit — programs with input() may legitimately
        // run for a long time waiting for the user.
        self.Sk.execLimit = undefined;
        self.Sk.yieldLimit = 100;
        self.Sk.configure({
            output: (text) => {
                // Flush immediately so prompts appear before the program blocks.
                self.postMessage(jsonMsg('stdout', String(text), session));
            },
            read: (x) => {
                if (self.Sk.builtinFiles === undefined || self.Sk.builtinFiles["files"][x] === undefined) {
                    throw "File not found: '" + x + "'";
                }
                return self.Sk.builtinFiles["files"][x];
            },
            inputfun: skulptInputFun,
            inputfunTakesPrompt: true,
            __future__: self.Sk.python3
        });

        await self.Sk.misceval.asyncToPromise(() => self.Sk.importMainWithBody("<stdin>", false, code, true));
        flushOutputs();
        self.postMessage(jsonMsg('done', '', session));
    } catch (error) {
        flushOutputs();
        stderrBuf += (error && error.toString ? error.toString() : String(error)) + '\n';
        flushOutputs();
        self.postMessage(jsonMsg('done', '', session));
    }
};
