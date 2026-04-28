# Locode IDE 🚀
### The Ultimate Mobile-First Development Environment

Locode is a professional-grade, high-performance IDE designed from the ground up for mobile devices. It combines a lightning-fast native code editor with a local execution engine and integrated AI assistance to provide a desktop-class coding experience in the palm of your hand.

---

## ✨ What Makes Locode Special?

Locode isn't just a text editor; it's a complete development ecosystem. Unlike other mobile editors that rely on slow web views for the entire UI, Locode uses a **Hybrid Native Architecture** to ensure that your typing feels instant and your layout remains stable.

### 💎 Key Features

*   **⚡ Native Performance Editor:** A custom-built Flutter code editor with low-latency input and intelligent syntax highlighting for C, C++, and Python.
*   **🤖 Locode AI Assistant:** A floating, non-intrusive AI chat that can generate code, explain complex logic, and perform **Side-by-Side Diff Reviews**. Integrated with state-of-the-art online LLMs for intelligent refactoring.
*   **🖥️ Integrated Terminal:** A fixed, professional-grade terminal that supports real-time stdin/stdout, allowing you to interact with your code as it runs.
*   **⚙️ Local Execution Engine:** Run your code directly on your device using Locode's isolated compiler service (WASM).
*   **📂 Professional File Management:** Full support for local disk access, "Save As" functionality, and a smart "Recent Files" system to keep your workflow organized.
*   **🌓 Adaptive UI:** Sleek Glassmorphism design with a high-contrast dark mode and a professional light mode, featuring theme-aware branding.
*   **🛠️ Smart UX:** Adaptive panels that automatically collapse when you start typing to maximize your screen real estate.

---

## 🏗️ Architecture & Technology Stack

Locode is built using a sophisticated multi-tier architecture to balance performance with flexibility:

1.  **UI Layer (Flutter):** Provides a beautiful, responsive, and platform-native interface.
2.  **Editor Core (Native Code Editor):** A custom implementation designed for high-performance text manipulation and syntax parsing on mobile hardware.
3.  **Execution Engine (Isolated Compiler):** Uses a secure, isolated WebView-based JS bridge to execute C++ and Python code using modern web-assembly technologies.
4.  **AI Intelligence (Locode AI):** Integrates with state-of-the-art LLMs (Llama 3 optimized) to provide contextual code assistance and intelligent refactoring.
5.  **Domain Layer:** Decoupled services for file handling, compiler management, and user settings, ensuring a clean and maintainable codebase.

---

## 🚀 Getting Started

1.  **Install:** Use the provided `Locode.apk` to install the IDE on your Android device.
2.  **Open:** Launch the app and use the "Browse" button to open an existing project or "New File" to start from scratch.
3.  **Code:** Use the native editor with full undo/redo support.
4.  **Run:** Tap the play icon to execute your code and interact with it in the Terminal.
5.  **AI Assist:** Tap the AI icon to open the Locode assistant for brainstorming or refactoring.

---

## 🛡️ Security & Privacy

Locode values your privacy:
*   **On-Device Persistence:** Your AI chat history is stored locally on your device using encrypted-safe shared preferences. 
*   **Privacy First:** Deleting a chat session permanently wipes it from your local storage.
*   **Secure API Access:** Locode uses a tiered secret management system to ensure your API keys are never leaked to public repositories while maintaining seamless functionality on your device.
*   **Sandboxed Execution:** Local code execution happens in a secure, isolated environment to ensure your data stays private.

---

## 🤖 Persistent AI History

Locode AI now features a full-scale session management system:
*   **Multiple Chats:** Create separate chat sessions for different projects or tasks.
*   **Tabbed Interface:** Easily switch between your "Current Chat" and your "All Chats" history.
*   **Deep Persistence:** Your conversations are saved automatically and remain available even after app restarts.

---

*Built with ❤️ by the Locode Team.*
