function parsePayload(data) {
  if (typeof data === 'string') {
    try { return JSON.parse(data); } catch (_) { return {}; }
  }
  return data || {};
}

function msg(type, data, session) {
  return JSON.stringify({ type, data, session });
}

function normalize(input) {
  let s = String(input || '')
    .replace(/^\uFEFF/, '')
    .replace(/[\u200B-\u200D\u2060]/g, '')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/^\s*```[a-zA-Z0-9]*\s*\n/, '')
    .replace(/\n```+\s*$/m, '\n');

  // The mobile bridge may pass JSON-encoded strings (wrapped in quotes) and
  // Dart's jsonEncode escapes < > as \u003C \u003E. Decode that here.
  // Example we observed: "\"#include \\u003Ciostream>\\nint main() { ... }\""
  if (s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"') {
    try {
      s = JSON.parse(s);
    } catch (_) {
      // Fall back to a conservative unescape if it isn't valid JSON.
      s = s.slice(1, -1)
        .replace(/\\n/g, '\n')
        .replace(/\\r/g, '\r')
        .replace(/\\t/g, '\t')
        .replace(/\\"/g, '"')
        .replace(/\\\\/g, '\\')
        .replace(/\\u003C/g, '<')
        .replace(/\\u003E/g, '>')
        .replace(/\\u0026/g, '&');
    }
  }
  return s;
}

let clangModulePromise;
async function getRunClang() {
  if (!clangModulePromise) {
    clangModulePromise = import('/web/clang/bundle.js');
  }
  const mod = await clangModulePromise;
  return mod.runClang;
}

function makeCapture() {
  const chunks = [];
  return {
    write(bytes) {
      if (bytes !== null) chunks.push(new Uint8Array(bytes));
    },
    text() {
      const len = chunks.reduce((n, c) => n + c.length, 0);
      const all = new Uint8Array(len);
      let off = 0;
      for (const c of chunks) {
        all.set(c, off);
        off += c.length;
      }
      return new TextDecoder().decode(all);
    },
  };
}

class WasiExit extends Error {
  constructor(code) {
    super(`WASI exit ${code}`);
    this.code = code;
  }
}

async function runWasmProgram(wasmBytes, stdinRaw = '', session = -1) {
  const stdinBytes = new TextEncoder().encode(String(stdinRaw));
  let stdinOffset = 0;
  let memory = null;
  let stdout = '';
  let stderr = '';

  // Persistent XHR input buffer: leftover bytes from one fd_read call are
  // reused by the next, so cin/scanf/getline don't trigger a new blocking XHR
  // for every character they peek at.
  let xhrBuf = new Uint8Array(0);
  let xhrBufOffset = 0;

  const decoder = new TextDecoder();

  function getU8() {
    if (!memory) return null;
    return new Uint8Array(memory.buffer);
  }

  function writeU32(ptr, value) {
    const u8 = getU8();
    if (!u8 || ptr + 4 > u8.length) return;
    const dv = new DataView(u8.buffer);
    dv.setUint32(ptr, value >>> 0, true);
  }

  function readBytes(ptr, len) {
    const u8 = getU8();
    if (!u8) return new Uint8Array();
    if (ptr < 0 || len < 0 || ptr + len > u8.length) return new Uint8Array();
    return u8.slice(ptr, ptr + len);
  }

  const wasi = {
    fd_write(fd, iovs, iovsLen, nwritten) {
      let written = 0;
      let buffer = '';
      for (let i = 0; i < iovsLen; i++) {
        const base = iovs + i * 8;
        const ptr = new DataView(getU8().buffer).getUint32(base, true);
        const len = new DataView(getU8().buffer).getUint32(base + 4, true);
        const chunk = decoder.decode(readBytes(ptr, len));
        buffer += chunk;
        written += len;
      }
      
      // Send output to UI immediately
      if (fd === 1) {
        self.postMessage(msg('stdout', buffer, session));
        stdout += buffer;
      } else {
        self.postMessage(msg('stderr', buffer, session));
        stderr += buffer;
      }
      
      writeU32(nwritten, written);
      return 0;
    },
    proc_exit(code) { throw new WasiExit(code); },
    environ_sizes_get(pCount, pBufSize) { writeU32(pCount, 0); writeU32(pBufSize, 0); return 0; },
    environ_get() { return 0; },
    args_sizes_get(pCount, pBufSize) { writeU32(pCount, 0); writeU32(pBufSize, 0); return 0; },
    args_get() { return 0; },
    clock_time_get(_id, _precision, outPtr) { writeU32(outPtr, 0); writeU32(outPtr + 4, 0); return 0; },
    fd_close() { return 0; },
    fd_prestat_get(_fd, _bufPtr) { return 8; }, // ENOTSUP
    fd_prestat_dir_name(_fd, _pathPtr, _pathLen) { return 8; }, // ENOTSUP
    fd_read(_fd, iovs, iovsLen, nwritten) {
      const u8 = getU8();
      if (!u8) {
        writeU32(nwritten, 0);
        return 0;
      }

      // Check if we have pre-filled stdin from payload
      if (stdinOffset < stdinBytes.length) {
        let written = 0;
        const dv = new DataView(u8.buffer);
        for (let i = 0; i < iovsLen; i++) {
          const base = iovs + i * 8;
          const ptr = dv.getUint32(base, true);
          const len = dv.getUint32(base + 4, true);
          if (stdinOffset >= stdinBytes.length) break;
          const take = Math.min(len, stdinBytes.length - stdinOffset);
          u8.set(stdinBytes.subarray(stdinOffset, stdinOffset + take), ptr);
          stdinOffset += take;
          written += take;
        }
        writeU32(nwritten, written);
        return 0;
      }

      // Drain leftover bytes from the previous XHR before doing a new one.
      // cin/scanf/getline all call fd_read multiple times per value read.
      // Without this buffer every peek would block on a fresh XHR.
      if (xhrBufOffset < xhrBuf.length) {
        let written = 0;
        const dv = new DataView(u8.buffer);
        for (let i = 0; i < iovsLen; i++) {
          const base = iovs + i * 8;
          const ptr = dv.getUint32(base, true);
          const len = dv.getUint32(base + 4, true);
          const take = Math.min(len, xhrBuf.length - xhrBufOffset);
          if (take <= 0) break;
          u8.set(xhrBuf.subarray(xhrBufOffset, xhrBufOffset + take), ptr);
          xhrBufOffset += take;
          written += take;
        }
        writeU32(nwritten, written);
        return 0;
      }

      // No buffered bytes left — block on XHR until user submits a line.
      try {
        const xhr = new XMLHttpRequest();
        xhr.open('GET', self.location.origin + '/stdin', false);
        xhr.send();

        if (xhr.status === 200 && xhr.responseText.length > 0) {
          xhrBuf = new TextEncoder().encode(xhr.responseText);
          xhrBufOffset = 0;

          let written = 0;
          const dv = new DataView(u8.buffer);
          for (let i = 0; i < iovsLen; i++) {
            const base = iovs + i * 8;
            const ptr = dv.getUint32(base, true);
            const len = dv.getUint32(base + 4, true);
            const take = Math.min(len, xhrBuf.length - xhrBufOffset);
            if (take <= 0) break;
            u8.set(xhrBuf.subarray(xhrBufOffset, xhrBufOffset + take), ptr);
            xhrBufOffset += take;
            written += take;
          }
          writeU32(nwritten, written);
          return 0;
        }
      } catch (e) {
        console.error('Interactive stdin XHR failed: ' + e);
      }

      writeU32(nwritten, 0);
      return 0;
    },
    fd_filestat_get(_fd, _bufPtr) { return 8; }, // ENOTSUP
    fd_fdstat_set_flags() { return 0; },
    fd_seek(_fd, _offL, _offH, _whence, newOffPtr) { writeU32(newOffPtr, 0); writeU32(newOffPtr + 4, 0); return 0; },
    fd_fdstat_get() { return 0; },
    path_open() { return 8; }, // ENOTSUP
    path_filestat_get() { return 8; }, // ENOTSUP
    random_get(bufPtr, bufLen) {
      const u8 = getU8();
      if (!u8) return 0;
      const cryptoObj = (typeof crypto !== 'undefined') ? crypto : null;
      if (cryptoObj && typeof cryptoObj.getRandomValues === 'function') {
        cryptoObj.getRandomValues(u8.subarray(bufPtr, bufPtr + bufLen));
      } else {
        for (let i = 0; i < bufLen; i++) u8[bufPtr + i] = (Math.random() * 256) | 0;
      }
      return 0;
    },
  };

  const imports = {
    wasi_snapshot_preview1: wasi,
    wasi_unstable: wasi,
    env: {
      emscripten_notify_memory_growth: () => {},
      emscripten_memcpy_big: () => {},
      __stack_chk_fail: () => { throw new Error('stack check failed'); },
      __cxa_allocate_exception: () => 0,
      __cxa_throw: () => {},
      __cxa_begin_catch: () => 0,
      __cxa_end_catch: () => {},
    },
  };

  const module = await WebAssembly.compile(wasmBytes);
  const instance = await WebAssembly.instantiate(module, imports);
  memory = instance.exports.memory || null;

  let exitCode = 0;
  try {
    if (typeof instance.exports._start === 'function') {
      instance.exports._start();
    } else if (typeof instance.exports.main === 'function') {
      exitCode = instance.exports.main(0, 0) | 0;
    } else {
      throw new Error('No runnable entrypoint (_start/main) found in wasm module');
    }
  } catch (e) {
    if (e instanceof WasiExit) {
      exitCode = e.code | 0;
    } else {
      throw e;
    }
  }

  return { stdout, stderr, exitCode };
}

self.onmessage = async function (e) {
  const payload = parsePayload(e.data);

  // Ignore stdin relay messages sent by writeStdin() — those are only used
  // as a signal to the /stdin XHR bridge; the worker does not handle them.
  if (payload.type === 'stdin') return;

  const session = payload.session ?? -1;
  const source = normalize(payload.code || '');

  if (!source.trim()) {
    self.postMessage(msg('stderr', 'C++ source is empty.\n', session));
    self.postMessage(msg('done', '', session));
    return;
  }

  self.postMessage(msg('stdout', 'Locode C++ compiler+run started (offline clang wasm).\n', session));

  const out = makeCapture();
  const err = makeCapture();
  try {
    const runClang = await getRunClang();
    const files = await runClang(
      ['clang++', '-std=c++17', '-fno-exceptions', '-fno-rtti', '-O0', '-Wall', '-Wextra', 'main.cpp', '-o', 'main.wasm'],
      { 'main.cpp': source },
      { stdout: out.write, stderr: err.write }
    );

    const stderr = err.text();
    const stdout = out.text();
    if (stdout.trim()) {
      self.postMessage(msg('stdout', stdout.endsWith('\n') ? stdout : `${stdout}\n`, session));
    }
    if (stderr.trim()) {
      self.postMessage(msg('stderr', stderr.endsWith('\n') ? stderr : `${stderr}\n`, session));
    } else {
      self.postMessage(msg('stdout', 'Compilation successful.\n', session));
    }

    const wasm = files?.['main.wasm'];
    if (!(wasm instanceof Uint8Array)) {
      self.postMessage(msg('stderr', 'Compile succeeded but main.wasm was not produced.\n', session));
      self.postMessage(msg('done', '', session));
      return;
    }

    const runResult = await runWasmProgram(wasm, payload.stdin || '', session);
    // Removed redundant final prints to prevent double-output (using streaming instead)
    self.postMessage(msg('done', '', session));
    self.postMessage(msg('stdout', `\n[Process exited with code ${runResult.exitCode}]\n`, session));
  } catch (errThrown) {
    const capturedOut = out.text();
    const capturedErr = err.text();
    if (capturedOut.trim()) {
      self.postMessage(
        msg('stdout', capturedOut.endsWith('\n') ? capturedOut : `${capturedOut}\n`, session),
      );
    }
    if (capturedErr.trim()) {
      self.postMessage(
        msg('stderr', capturedErr.endsWith('\n') ? capturedErr : `${capturedErr}\n`, session),
      );
    }

    const code = (errThrown && typeof errThrown.code === 'number') ? errThrown.code : 1;
    const text = (errThrown && errThrown.message) ? errThrown.message : String(errThrown);
    if (!capturedErr.trim()) {
      self.postMessage(msg('stderr', `C++ compiler exited with status ${code}.\n${text}\n`, session));
    } else {
      self.postMessage(msg('stderr', `C++ compiler exited with status ${code}.\n`, session));
    }
  }

  self.postMessage(msg('done', '', session));
};
