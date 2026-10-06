# ADR-001: Windows runtime and packaging boundary

Status: Accepted for Phase 0
Date: 2026-10-07

## Context

The product is a Windows x64 installer and manager for a local ERPNext site.
It needs native access to UAC, Windows features, WSL, Scheduled Tasks, DPAPI,
filesystem ACLs, and Docker Desktop while remaining supportable after a reboot.

## Decision

- Build the manager and installation workflow as a self-contained .NET 10 LTS
  WPF x64 application.
- Keep orchestration in reusable Core, Windows, Docker, and Security libraries.
- Prove the first provisioning path with a console entry point that calls those
  same libraries; it is not a disposable script.
- Use WiX packaging only after the executable manager is working. Installer MSI
  custom actions must not own long-running pulls, reboot resume, or data changes.

## Consequences

- The development/build environment requires the .NET 10 SDK.
- Phase 1 can create the solution and test harness without committing to final
  WiX packaging details.
- The WPF UI remains an orchestration client, not the owner of installation
  state or privileged commands.
