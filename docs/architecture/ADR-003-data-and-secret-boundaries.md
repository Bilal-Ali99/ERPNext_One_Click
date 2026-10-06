# ADR-003: Data, backup, and secret boundaries

Status: Accepted for Phase 0
Date: 2026-10-07

## Decision

- Scope every container, volume, generated runtime file, and cleanup operation
  to one installer-generated instance ID.
- Keep live sites and database storage in named Docker volumes.
- Bind-mount a separate host backup directory outside resettable runtime and
  volume paths.
- Store secrets only in Windows DPAPI-protected storage and materialize them in
  short-lived, ACL-restricted files when a container command requires them.
- Never put secrets in logs, command arguments, state JSON, or committed assets.

## Consequences

- Reset can whitelist only known instance resources while preserving backups.
- The manager must ask for a password again if secure secret recovery is not
  possible after interruption.
- Backup/restore behavior is part of the catalog-promotion test gate.
