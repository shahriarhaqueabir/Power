# State of the Art Research (July 2026)

## Tabby.sh Features
- **Self-Hosted Privacy**: Private RAG for codebase.
- **Answer Engine**: Indexes internal repos/docs.
- **Pochi Agent**: Multi-step autonomous task handling.
- **Inline Chat**: Refactoring and test generation.

## 2026 PowerShell Ecosystem
- **Intelligent Terminal**: Native AI pane, ACP support, Error recovery buttons.
- **PowerShell 7.6 LTS**: .NET 10, high-perf intrinsics (`PSForEach`), better tab completion.
- **AI-First Shell**: PSReadLine 2.4.5 predictors, FeedbackProvider hooks.

## Comparison & Recommendations for PowershellOps
1. **From Keyword to Vector**: Current memory is too simple. Need semantic search.
2. **From Memory to RAG**: Need to index the codebase, not just manual notes.
3. **From Single-Shot to Agentic**: Upgrade `Invoke-OpsAI` to a task-loop agent.
4. **Integration**: Deepen shell integration via `$Error` hooks.
