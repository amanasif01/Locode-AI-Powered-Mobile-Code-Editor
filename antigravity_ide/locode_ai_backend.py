import os
import sys
import subprocess

def install_dependencies():
    packages = ["fastapi", "uvicorn", "pydantic", "httpx"]
    for pkg in packages:
        try:
            __import__(pkg.replace('-', '_'))
        except ImportError:
            print(f"Installing missing dependency: {pkg}...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", pkg])

install_dependencies()

from fastapi import FastAPI, HTTPException
import uvicorn
from pydantic import BaseModel
from typing import Optional
from fastapi.middleware.cors import CORSMiddleware
import httpx

app = FastAPI(title="Locode AI Backend – Llama 3 Online")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Online Llama 3 via Groq ───────────────────────────────────────────────────
GROQ_API_KEY   = os.environ.get("GROQ_API_KEY", "") # Redacted for security
GROQ_API_URL   = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL     = "llama-3.3-70b-versatile"

# ── Request / Response Models ─────────────────────────────────────────────────
class ChatMessage(BaseModel):
    text: str
    is_user: bool

class OnlineOptions(BaseModel):
    include_context: bool = True
    mode: str = "chat"          # "chat" | "modify" | "rewrite"

class ChatRequest(BaseModel):
    message: str
    file_name: str = ""
    file_content: str = ""
    history: list[ChatMessage] = []
    model_type: str = "online"           # Default to online
    options: Optional[OnlineOptions] = None

class PythonRunRequest(BaseModel):
    code: str
    timeout_seconds: int = 8

# ── Helper: build system prompt based on mode ─────────────────────────────────
def _build_system_prompt(mode: str, has_file: bool) -> str:
    base = "You are Locode, an AI coding assistant embedded in an IDE.\n\n"

    if mode == "modify":
        instructions = (
            "OUTPUT RULES:\n"
            "1. Output ONLY the complete, corrected or modified code in a single markdown codeblock (e.g. ```python).\n"
            "2. Do NOT output the entire file unless you changed more than half of it. Output only the modified function/block.\n"
            "3. Do NOT provide any explanation or text outside the codeblock.\n"
            "4. If the user asks a question rather than requesting a change, answer in plain text.\n"
        )
    elif mode == "rewrite":
        instructions = (
            "OUTPUT RULES:\n"
            "1. Output a COMPLETE, production-ready rewrite of the entire file in a single markdown codeblock.\n"
            "2. Preserve all existing functionality unless the user explicitly asks to remove it.\n"
            "3. Do NOT provide explanations or conversational text. Output ONLY the codeblock.\n"
        )
    else:  # chat
        instructions = (
            "OUTPUT RULES:\n"
            "1. Write requested code modifications or new code in standard markdown codeblocks (e.g. ```dart).\n"
            "2. ONLY output the code that needs to be inserted, replaced, or written. Do NOT output the entire file unless explicitly requested.\n"
            "3. DO NOT provide any explanation or conversational text unless the user explicitly asks for one.\n"
        )

    return base + instructions

# ── /chat endpoint ────────────────────────────────────────────────────────────
@app.post("/chat")
async def chat(req: ChatRequest):
    opts         = req.options or OnlineOptions()
    mode         = opts.mode
    use_context  = opts.include_context

    # Build file context string
    context_str = ""
    if use_context and req.file_name:
        content     = req.file_content.strip() if req.file_content.strip() else "(empty file)"
        context_str = f"FILE: {req.file_name}\n```\n{content}\n```\n\n"

    system_prompt = _build_system_prompt(mode, bool(context_str))

    # ── ONLINE: Llama 3 via Groq API ─────────────────────────────────────────
    messages = [{"role": "system", "content": system_prompt}]

    # Build history (exclude the latest user message — sent separately)
    for msg in req.history[:-1]:
        role = "user" if msg.is_user else "assistant"
        messages.append({"role": role, "content": msg.text})

    # Final user message includes optional file context
    user_content = f"{context_str}{req.message}"
    messages.append({"role": "user", "content": user_content})

    print(f"[Llama 3 Online / Groq] mode={mode} context={bool(context_str)} messages={len(messages)}")

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(
                GROQ_API_URL,
                headers={
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": GROQ_MODEL,
                    "messages": messages,
                    "max_tokens": 4096,
                    "temperature": 0.2,
                },
            )
        res.raise_for_status()
        data  = res.json()
        reply = data["choices"][0]["message"]["content"].strip()
        return {"reply": reply}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=502, detail=f"Groq API error: {e.response.text}")
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Online model error: {str(e)}")

@app.post("/run_python")
async def run_python(req: PythonRunRequest):
    code = req.code or ""
    timeout_seconds = max(1, min(req.timeout_seconds, 20))
    try:
        proc = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        return {
            "ok": proc.returncode == 0,
            "exit_code": proc.returncode,
            "stdout": stdout,
            "stderr": stderr,
        }
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "exit_code": -1,
            "stdout": "",
            "stderr": f"Execution timed out after {timeout_seconds}s\n",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Python runner failed: {e}")

if __name__ == "__main__":
    print("Starting Locode AI Backend Runner...")
    uvicorn.run("locode_ai_backend:app", host="127.0.0.1", port=8000, reload=False)
