# Phase 0 host-readiness checklist

This checklist identifies what a development or release-validation machine needs
before running the first executable vertical slice. It does not authorize or
perform machine-wide changes.

## Build machine

- .NET 10 SDK installed and available as `dotnet`.
- Windows x64 development environment.
- Git access to this repository.

## Provisioning test machine

- Supported Windows 10/11 build and x64 hardware.
- Firmware virtualization and SLAT enabled.
- WSL2 installed at or above the catalog minimum.
- Docker Desktop running with Linux containers and WSL2 backend.
- Sufficient local space for the test stack and a distinct backup path.
- No customer or production data.

## Current local observation (2026-10-07)

- WSL 2.6.3.0 is available.
- Docker CLI 29.3.1 is present but its engine was not running.
- The .NET SDK was not available on PATH.

Start Docker Desktop and install the SDK only when the user authorizes those
machine-wide changes. Re-run the installer pre-flight checks instead of relying
on this document as proof of readiness.
