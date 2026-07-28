# PowershellOps: Architectural North Star & Companion Guidelines

This document outlines the state-of-the-art (SOTA) architectural decisions and coding standards for the PowershellOps AI Companion, based on 2026 terminal ecosystem research and best practices from leading GitHub AI projects (Open Interpreter, AIChat, Fabric).

## 1. The North Star Vision
PowershellOps is a **Local-First Agentic Stack**. It transforms the terminal from a command execution shell into an **Intelligent Companion Hub** that reasons over local context, researches online information, and executes workflows autonomously using private local LLMs.

## 2. Tiered Architectural Stack (Hexagonal Design)

To maintain a lightweight and maintainable codebase, we follow a tiered "Ports & Adapters" pattern:

| Layer | Responsibility | Key Component |
| :--- | :--- | :--- |
| **Public (Ports)** | Intent-driven user entry points. High-level aliases. | `hub`, `ask`, `fix`, `stat` |
| **Service (Logic)** | Orchestration, intent classification, and RAG logic. | `Invoke-OpsCompanion`, `Invoke-OpsAI` |
| **Adapter (Infra)** | Low-level execution (CIM/WMI, REST, Web, AI API). | `Invoke-RestMethod`, `Get-CimInstance`, `Invoke-OpsSearch` |
| **Memory (State)** | Persistent vector-indexed session and long-term storage. | `Search-OpsMemory`, `Add-OpsMemory` |

## 3. Core Architectural Decisions

### A. Local-First Privacy (The "Black Box" Principle)
- **Decision**: All reasoning and embedding generation must happen locally (Ollama/llama.cpp).
- **Tooling**: Ollama (Inference), `nomic-embed-text` (Embeddings).
- **Constraint**: No data leaves the machine unless the user explicitly triggers `-Online` or `web` research modes.

### B. Agentic Feedback Loops
- **Inspired by**: Open Interpreter.
- **Implementation**: The companion doesn't just "answer"; it **proposes and verifies**.
- **Pattern**: `Plan -> Propose -> Execute -> Analyze Output -> Self-Correct`.

### C. Pattern-Based Prompting
- **Inspired by**: Fabric.
- **Implementation**: System prompts are stored as structured "Patterns" in `modelfiles/` or `Config/AI/`.
- **Constraint**: Avoid hardcoding complex logic in string blocks; use structured JSON/Markdown patterns.

### D. Semantic RAG (Retrieval-Augmented Generation)
- **Implementation**: Hybrid Search (Keyword + Vector).
- **Optimization**: Use **Semantic Chunking** for codebase indexing. When searching the codebase, prioritize functions, class definitions, and comments.

## 4. Coding Standards & Best Practices

- **Object-Oriented Output**: Always return `[PSCustomObject]`. This allows the AI to "reason" over structured data rather than fragile text parsing.
- **Server-Side Filtering**: In CIM/WMI adapters, use `-Filter` at the source.
- **Structured AI Output**: Use "JSON Mode" for internal tool calls (e.g., intent classification) to ensure programmatic reliability.
- **Ambient Context Injection**: Every AI request should automatically include:
    - `[DateTime]`
    - `[SystemLoad]`
    - `[ActiveProjectRoot]`
    - `[LastError]`

## 5. Implementation Roadmap (The "Hub" Strategy)

1. **The Hub (`hub`)**: A central entry point that uses `Get-OpsAIIntent` to route between:
    - `Research`: Web Search + Synthesis.
    - `Diagnostic`: System Health + Security Scan.
    - `Memory`: Semantic Retrieval of notes/preferences.
    - `Workflow`: Multi-step command execution.

2. **The Fix (`fix`)**: An automated "Healing Port" that hooks into the shell's `$Error` stream.

3. **The Brief (`hub brief`)**: A daily driver that aggregates Online Research (Top News) + Local State (System Health) into a single AI-synthesized report.

---
*Date: July 27, 2026*
*Alignment: System diagnostics, security auditing, and AI-first engineering.*
