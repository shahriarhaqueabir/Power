# Sprint 1: 2026 AI-First Modernization

## Overview
Modernize PowershellOps to align with 2026 state-of-the-art terminal standards and Tabby-style self-hosted RAG capabilities.

## Kanban Board

| ID | Ticket | Status | Priority | DOD |
|----|--------|--------|----------|-----|
| T-01 | **Vector Memory Integration** | 🔲 TODO | High | - [ ] Implement semantic search using Ollama `/api/embeddings`.<br>- [ ] Update `Search-OpsMemory` to support hybrid (keyword + vector) scoring. |
| T-02 | **Codebase Indexer (RAG)** | 🔲 TODO | High | - [ ] Index `Modules/PowershellOps` source code.<br>- [ ] Provide context-aware answers for module-specific queries. |
| T-03 | **Autonomous Task Loop** | 🔲 TODO | Medium | - [ ] Implement `Invoke-OpsAgent` for multi-step tasks.<br>- [ ] Support command proposal and verification loops. |
| T-04 | **Error Feedback Provider** | 🔲 TODO | Medium | - [ ] Hook into `$Error` to suggest fixes via AI.<br>- [ ] Add "Fix it" prompt to dashboard. |
| T-05 | **ACP Bridge** | 🔲 TODO | Low | - [ ] Implement Agent Client Protocol stubs for Intelligent Terminal compatibility. |

## Baseline State
- Build: `./Invoke-OpsBuild.ps1` passes.
- Test Count: ~23,000 lines of test logic (from `PowershellOps.Tests.ps1` size). Wait, the file size was 23KB, not 23K tests. `AGENTS.md` says 594 lines.
- Lint: PSScriptAnalyzer 1.2x.
