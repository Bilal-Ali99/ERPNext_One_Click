# ADR-002: Immutable release catalog and Compose source policy

Status: Accepted for Phase 0
Date: 2026-10-07

## Decision

- Use official `frappe/frappe_docker` service conventions as the source design.
- Model v15 and v16 candidates in `assets/release-catalog.json`.
- Permit installation only from catalog entries marked `approved`.
- An approved entry must contain the exact `sha256` digest for the ERPNext,
  MariaDB, and Redis images; a pinned upstream Compose commit; and test evidence.
- Generate runtime Compose files from the approved catalog. Do not use `latest`
  or an unpinned image tag at installation time.

## Consequences

- Candidate tags are discovery aids, not installable release versions.
- The installer can give a clear unsupported-version error rather than pulling a
  newly moved tag.
- A release promotion process is required whenever ERPNext, Frappe Docker, or a
  dependency changes.

See `docs/operations/RELEASE_CATALOG.md` and
`docs/architecture/COMPOSE_INTEGRATION.md`.
