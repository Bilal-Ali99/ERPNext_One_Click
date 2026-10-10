# ERPNext / Frappe Windows Installer

This repository builds a Windows installer for one local ERPNext/Frappe site.
It uses Docker Desktop with the WSL2 backend so Python, Node.js, MariaDB, and
Redis are not installed directly on the Windows host.

The functional requirements are in
[`docs/erpnext-windows-installer-spec.md`](docs/erpnext-windows-installer-spec.md).
The implementation uses Inno Setup as the `.exe` wrapper and Windows
PowerShell 5.1+ for host-side orchestration.

## Current status

The repository currently contains the safe installer foundation: state and log
modules, a read-only preflight script, orchestration entry point, Pester tests,
and an Inno Setup scaffold. It does **not** yet enable Windows features,
install Docker, create containers, create an ERPNext site, or modify user data.

## Developer checks

Run the PowerShell test suite:

```powershell
Invoke-Pester .\tests
```

Run a non-mutating preflight preview:

```powershell
.\installer\scripts\preflight.ps1 -WhatIf
```

After Inno Setup is installed, compile the installer with:

```powershell
iscc .\installer\setup.iss
```

Never test feature enablement, Reset, container teardown, or storage compaction
on a machine with real customer data. Use a disposable VM or Windows Sandbox.
