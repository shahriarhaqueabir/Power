# Project Rules — PowershellOps

PowerShell 7 module and profile for system diagnostics, security auditing, and AI integrations.

## Stack
- **Language**: PowerShell 7+ (requires `pwsh`)
- **Module root**: `Modules/PowershellOps/`
- **Manifest**: `Modules/PowershellOps/PowershellOps.psd1`
- **Tests**: `Modules/PowershellOps/Tests/PowershellOps.Tests.ps1` (Pester 5+)
- **Build script**: `Invoke-OpsBuild.ps1`

## Test Commands

Run these to verify changes:

```powershell
# Full build + lint + tests
./Invoke-OpsBuild.ps1

# Tests only (skip analyzer)
./Invoke-OpsBuild.ps1 -SkipAnalyzer

# Analyzer only (skip tests)
./Invoke-OpsBuild.ps1 -SkipTests
```

If `Invoke-OpsBuild.ps1` fails, stop and fix before proceeding.

## Code Conventions

- **Prefix functions with `Ops`**: `Get-OpsSomething` — predictable tab-completion, no collisions
- **Add aliases in `Set-OpsAliases`**: Users should never type the full function name
- **Add dashboard entry in `Show-OpsDashboard`**: New commands must appear in the startup UI
- **Use `[CmdletBinding()]`**: Enables `-Verbose`, `-ErrorAction`, and `-WhatIf`
- **Output `[PSCustomObject]`**: Pipes cleanly into Format-Table, ConvertTo-Json, and the report engine
- **`-ErrorAction SilentlyContinue` on reads, `Stop` on writes**: Audit functions must not crash the session
- **Dispose HttpClient/streams in `finally` blocks**: Avoid memory pressure over long sessions

## Forbidden Paths — Do Not Modify

- `.git/` — version control internals
- `Modules/*/` except `Modules/PowershellOps/` — third-party modules installed via `Install-OpsPrerequisite`
- `*.key`, `*.pem`, `*.pfx`, `*.crt`, `*.p12` — certificates and keys
- `.env`, `.env.*`, `secrets.*`, `credentials.*` — secrets

## Forbidden Actions

- Do not modify `PowershellOps.psd1` function exports without running the full test suite
- Do not add external dependencies without explicit user approval
- Do not change the dashboard UI layout without confirming with user
- Do not commit secrets, tokens, or credentials — check `.gitignore` patterns

## Verification Checklist

After any code change, confirm:

1. `./Invoke-OpsBuild.ps1` passes (analyzer + tests)
2. No new PSScriptAnalyzer warnings introduced
3. New functions follow `Verb-OpsNoun` naming
4. New functions are exported in the manifest
5. New functions appear in the dashboard

## Architecture Notes

- **Public/**: User-facing functions (imported by the module)
- **Private/**: Internal helpers (not exported, used by Public functions)
- **Tests/**: Pester test suite — 594 lines covering module import, system diagnostics, security, memory, network, AI, onboarding, and workflow commands
- **Config/**: Static configuration data
- **modelfiles/**: AI model configuration files
