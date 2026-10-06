# Compose integration contract

## Source baseline

Runtime files derive from the approved revision of official `frappe_docker`:

- `compose.yaml`
- `overrides/compose.mariadb.yaml`
- `overrides/compose.redis.yaml`

The current source model supplies `configurator`, `backend`, `frontend`,
`websocket`, `queue-short`, `queue-long`, `scheduler`, `db`, `redis-cache`, and
`redis-queue`.

## Required installer deltas

Generated Compose files must:

1. resolve all image references from an **approved** release-catalog entry as
   `repository@sha256:<digest>`;
2. use an instance-scoped Compose project name and labels;
3. publish only `127.0.0.1:<selected-port>:8080` from `frontend`;
4. publish no MariaDB or Redis ports;
5. retain the MariaDB health gate before configuration and site creation;
6. use a one-shot site-creation action that runs `bench new-site` with
   `--install-app erpnext`, then verifies and explicitly enables the scheduler;
7. use named volumes for database and site data;
8. bind-mount the selected host backup directory only where the backup command
   needs it; and
9. use secret files or equivalent protected transport rather than environment
   values or command-line passwords.

## Contract test before promotion

On a clean supported Windows x64/WSL2 machine, the catalog candidate must prove:

1. `docker compose config` succeeds using generated runtime files;
2. all images resolve to the recorded digests;
3. MariaDB becomes healthy before site creation begins;
4. the created site serves a successful local HTTP response;
5. ERPNext appears in the installed-app list and the scheduler is enabled;
6. `docker port` reports no published database or Redis endpoint;
7. a complete backup and restore round trip preserves sample records and
   attachments; and
8. Repair preserves live data while Reset preserves the external backup folder.

Only then may the entry become `approved` in the catalog.
