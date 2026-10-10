# ADR-001: Inno Setup wrapper and PowerShell orchestration

Status: Accepted

Date: 2026-10-11

## Decision

- Use Inno Setup to compile the Windows installer executable.
- Use PowerShell 5.1-compatible scripts for all host-side orchestration.
- Keep installer state in the JSON path mandated by `AGENTS.md`.
- Use Pester for PowerShell tests.

## Rationale

Windows already provides PowerShell and the administrative interfaces needed
for WSL, Windows features, Docker detection, scheduled tasks, and filesystem
operations. This avoids adding a second host runtime for orchestration.

## Consequences

The former .NET/WPF/WiX prototype is superseded and is not part of the
installer runtime. A self-contained .NET helper may only be introduced through
an explicit future architecture decision; it must not create a competing state
machine or orchestration path.
