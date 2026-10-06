# ERPNext One-Click Windows Installer — Execution Plan

Plan version: 0.1  
Specification baseline: 1.0  
Prepared: 2026-09-28

## 1. Goal and definition of done

Build a Windows x64 application that installs and manages a single local ERPNext site through Docker Desktop's WSL2 backend. The user must never need to install or operate Python, Node.js, Redis, MariaDB, Bench, Docker Compose, or Linux directly.

Version 1 is complete when a supported Windows 10/11 machine can:

1. pass or clearly fail pre-flight checks;
2. enable required WSL2 features and safely resume after a user-approved reboot;
3. install or reuse a compatible Docker Desktop installation;
4. install an exactly pinned ERPNext v15 or v16 stack;
5. survive close, crash, reboot, and rerun at every installation stage;
6. create, verify, back up, start, stop, repair, and reset one site without silently losing data;
7. expose only the local web endpoint to Windows, with MariaDB and Redis remaining private;
8. produce supportable logs with no passwords or generated secrets; and
9. pass the acceptance matrix in section 9 of this plan.

## 2. Baseline corrections and release gates

The product intent in the specification is sound, but several values are time-sensitive. They must be represented by a tested release catalog, not scattered constants.

| Specification item | Execution decision |
|---|---|
| Windows 10 build 19041+ | Do not use this as the shipping minimum. Current Docker Desktop documentation requires Windows 10 22H2 build 19045 and Windows 11 23H2 build 22631 or later. Reconfirm immediately before every release. |
| Hyper-V and WSL2 | For the WSL2 backend, require WSL, Virtual Machine Platform, SLAT, and firmware virtualization. Do not require the full Hyper-V feature on editions/configurations where Docker's WSL2 backend does not need it. |
| 8 GB RAM is a soft recommendation | Current Docker prerequisites list 8 GB. Treat less than 8 GB as a warning in the product only if the chosen, tested Docker release still operates; otherwise promote it to a release-catalog hard blocker. |
| ERPNext v16 uses Python 3.12+ and Node 22+ | Current official Frappe Docker v16 builds use Python 3.14 and Node 24. The installer will consume a tested ERPNext image digest, so host logic never independently chooses Python or Node versions. |
| `.wslconfig` has no disk-size control | Current WSL documents `defaultVhdSize`, which is a maximum VHD size. Do not use it as a 45 GB artificial cap. Keep the 45 GB capacity baseline and disk monitoring; treat WSL disk settings as version-gated capabilities. |
| Run `bench get-app erpnext` | The official `frappe/erpnext` image already contains ERPNext. Prefer an exact image digest followed by site creation with ERPNext installation. Do not mutate a running container with `get-app` unless a proof-of-concept shows a supported image requires it. |
| Check host ports 8000, 3306, 6379, 80, and 443 | Report conflicts as requested, but only the selected web port is published. Host conflicts on 3306/6379 cannot affect internal-only database/Redis services. Ports 80/443 are informational in v1 because HTTPS is out of scope. |
| Silent scheduled compaction | Never allowed. The monthly task opens the manager and asks for consent. It warns that `wsl --shutdown` affects all running WSL distributions, not just ERPNext. |

Every production release must pin and test:

- the ERPNext image by immutable digest;
- MariaDB and Redis images by immutable digest, matching that ERPNext line;
- the Compose files and schema revision;
- minimum and maximum tested Docker Desktop versions;
- minimum WSL version and supported Windows builds; and
- hashes and source URLs for any downloaded installer.

Authoritative references to recheck at release time:

- [Docker Desktop on Windows requirements and installer flags](https://docs.docker.com/desktop/setup/install/windows-install/)
- [Docker Desktop license terms](https://docs.docker.com/subscription-billing/desktop-license/)
- [Official Frappe Docker repository](https://github.com/frappe/frappe_docker)
- [Frappe Bench backup reference](https://docs.frappe.io/framework/user/en/bench/reference/backup)
- [Microsoft WSL configuration reference](https://learn.microsoft.com/windows/wsl/wsl-config)

## 3. Product architecture

### 3.1 Technology choices

- **Manager and wizard:** self-contained .NET 10 LTS WPF x64 application. WPF is mature on Windows and supports the UAC, Scheduled Task, registry, process, and tray integrations needed here.
- **Packaging:** WiX Toolset bootstrapper/MSI that installs the manager, assets, shortcuts, and uninstall registration. Provisioning remains in the manager's resumable state machine rather than MSI custom actions.
- **Container runtime:** Docker Desktop using Linux containers and the WSL2 backend.
- **ERP stack:** official `frappe/erpnext` production image and official `frappe_docker` service conventions, adapted only through reviewed Compose overrides.
- **Automation boundary:** all operating-system work is performed through typed C# services. PowerShell/DISM is used only behind narrow adapters with captured exit codes and redacted output.
- **Target architecture:** Windows x64 only for v1. ARM64 and Windows Server are explicit hard blockers.

### 3.2 Installed components

1. **ERPNext Manager** — wizard plus Start, Stop, Open, Status, Backup, Restore, Repair, Reset, and diagnostics actions.
2. **Elevated helper** — a small, separately invoked process for feature enablement, scheduled-task creation, protected machine writes, and compaction. It accepts a strict command allow-list; it is not a general elevated shell.
3. **Compose bundle** — immutable, versioned templates and an embedded release catalog.
4. **Tray/shortcut integration** — launches the manager; it does not keep credentials in memory or attempt to replace Docker Desktop.
5. **Scheduled tasks** — resume-after-reboot, daily backup, disk monitoring, and monthly consent prompt for compaction.

### 3.3 Data locations

Use stable paths and explicitly separate live data from backups:

```text
%ProgramFiles%\ERPNext One Click\                 # signed binaries and immutable assets
%ProgramData%\ERPNextOneClick\
  state\installation.json                        # atomic, versioned state
  secrets\                                       # DPAPI-protected secrets only
  runtime\<instance-id>\                         # generated Compose/env files
  backups\<instance-id>\                         # host bind mount, never removed by Reset
  diagnostics\                                   # machine-level diagnostic bundles
%LOCALAPPDATA%\ERPNextInstaller\logs\             # user-readable redacted logs
```

State, secret, and runtime directories receive restricted ACLs. Passwords never appear in Compose command arguments, `.env`, state JSON, UI telemetry, or logs. Site and database secrets are stored with Windows DPAPI and materialized only through a short-lived, ACL-restricted temporary secret file when Docker/Bench requires them. The file is deleted in a `finally` path. If secure continuation cannot be guaranteed, the user is asked to re-enter the password on resume.

### 3.4 Proposed repository structure

```text
ERPNext_One_Click/
  ERPNextOneClick.sln
  Directory.Build.props
  README.md
  LICENSES/
  docs/
    EXECUTION_PLAN.md
    REQUIREMENTS_TRACEABILITY.md
    architecture/
    operations/
    test-plans/
  src/
    Manager.App/                         # WPF screens and tray UI
    Manager.Core/                        # state machine, policies, domain models
    Manager.Windows/                     # UAC, DISM, WSL, registry, tasks, firewall
    Manager.Docker/                      # Docker CLI/Compose adapters and health checks
    Manager.Security/                    # DPAPI, redaction, secret lifecycle
    ElevatedHelper/                      # allow-listed privileged operations
    Installer.Bootstrapper/              # WiX bundle/MSI
  assets/
    compose/
      base.yaml
      mariadb.yaml
      redis.yaml
      windows-local.yaml
    release-catalog.json
    eula/
  tests/
    Unit/
    Contract/
    Integration/
    WindowsE2E/
    Security/
  tools/
    Build/
    ReleaseCatalog/
    TestLab/
```

## 4. Resumable state machine

The state file uses a schema version, instance ID, selected catalog entry, current stage, completed stages, retry counts, timestamps, and sanitized error metadata. Writes use `write temporary -> flush -> atomic replace`, retaining one last-known-good copy.

Stages are idempotent: before acting, each stage checks its postcondition. A completed stage is skipped only when the postcondition still holds.

```text
NotStarted
  -> PreflightPassed
  -> FeaturesReady | FeaturesEnabledPendingRestart
  -> DockerReady
  -> ConfigurationCaptured
  -> RuntimePrepared
  -> ImagesPulled
  -> InfrastructureHealthy
  -> SiteCreated
  -> ERPNextInstalled
  -> SchedulerEnabled
  -> BackupConfigured
  -> MaintenanceConfigured
  -> Verified
  -> Completed
```

Failure is recorded as `Failed(stage, safe_message, diagnostic_id)` without erasing the last completed stage. Cancel is a user action, not a failure. On relaunch:

- **Resume** continues from the earliest incomplete or invalidated postcondition.
- **Repair** revalidates binaries, catalog, Compose files, containers, networks, volumes/binds, health, scheduler, and tasks; it recreates replaceable infrastructure but preserves data.
- **Reset** requires two confirmations naming the site and consequence. It offers a final backup, stops the scoped Compose project, and deletes only resources carrying the exact instance/project labels or whitelisted runtime paths. The backup directory is never targeted.
- **Cancel** exits without modifying live data.

The reboot stage registers a one-time, current-user Scheduled Task with an exact executable path and a random resume token. The task is removed after successful relaunch. The installer never calls a restart command until the user clicks **Restart Now**.

## 5. Runtime and Compose design

Use these services, following current official Frappe Docker conventions:

- `configurator` (one-shot)
- `backend`
- `frontend` (Nginx)
- `db` (MariaDB)
- `redis-cache`
- `redis-queue` (also used for Socket.IO)
- `scheduler`
- `queue-short`
- `queue-long`
- `websocket`
- `create-site` (one-shot and removed/disabled after success)

Key rules:

- Publish only `127.0.0.1:<chosen-port>:8080` from `frontend`.
- Do not publish MariaDB 3306 or Redis 6379.
- Keep `redis_cache`, `redis_queue`, and backward-compatible `redis_socketio` settings aligned with official conventions.
- Use a MariaDB health check based on an authenticated `mysqladmin ping` and make `create-site` depend on `service_healthy`. No fixed sleeps.
- Store sites and database data in explicitly named, instance-scoped persistent volumes. Bind-mount the separate host backup directory.
- Run services as their image-defined non-root users where supported. Any exception must be documented in an architecture decision record.
- Start from official production Compose files, keep the local delta small, and run a contract test against every catalog entry.
- Create the site and install ERPNext using the command supported by the pinned image. Then explicitly run `bench --site <site> enable-scheduler` and verify the result.

The completion probe must validate the frontend HTTP response, site/database connectivity, installed-app list containing ERPNext, scheduler enabled state, all long-running containers healthy/running, and absence of published database/Redis ports.

## 6. Implementation work plan

### Phase 0 — Resolve product and legal gates

Deliverables:

- signed-off Docker Desktop redistribution/download approach and customer EULA wording;
- exact Windows x64 support matrix;
- exact ERPNext v15 and v16 patch releases and image digests;
- decision on default site naming (`<name>.localhost` is preferred for local routing);
- destructive Reset wording and backup-location policy;
- architecture decision records for WPF/.NET, WiX, storage, and secret handling.

Exit gate: two clean manual installations—one for each ERPNext line—using the exact proposed images and Compose bundle.

### Phase 1 — Solution skeleton and engineering controls

Create the repository structure, solution, dependency pinning, analyzers, deterministic builds, CI, unit-test baseline, structured logging with mandatory redaction, and a build-generated software bill of materials.

Exit gate: a clean machine can build, test, and package the empty manager from one documented command.

### Phase 2 — Pre-flight engine

Implement each check as an independent result object with status (`Pass`, `Warning`, `Block`), evidence, remediation text, and a stable support code:

- Windows edition, architecture, version, build, and servicing support;
- elevation and UAC relaunch;
- SLAT/firmware virtualization;
- WSL, Virtual Machine Platform, WSL version, and WSL2 functional probe;
- known policy/feature denial conditions, plus a real WSL command probe;
- free space on both Docker data and backup target drives: block below 20 GB, warn below 45 GB;
- RAM according to the release catalog;
- DNS plus HTTPS reachability to every required registry/download endpoint;
- TCP listeners on 8000, 3306, 6379, 80, and 443, including owning process where permitted;
- Windows Firewall profiles and a post-Docker networking probe;
- Docker Desktop presence, version, backend, engine readiness, Linux-container mode, and existing unrelated workloads;
- proxy/VPN detection as a clear unsupported warning in v1.

Exit gate: table-driven unit tests for every boundary and E2E tests for representative blocking/warning machines.

### Phase 3 — WSL2 enablement and reboot resume

Implement feature discovery, enable only missing WSL/Virtual Machine Platform components with `/norestart`, persist `FeaturesEnabledPendingRestart`, present Restart Now/Later, register the one-time resume task, and verify WSL after login. Preserve existing `.wslconfig` settings; modify memory/processors only after showing a diff and obtaining consent. Write via safe merge, never overwrite the entire user file.

Exit gate: tests cover features already enabled, feature enablement requiring reboot, Restart Later, task relaunch, failed feature enablement, and policy denial.

### Phase 4 — Docker lifecycle

Detect Docker Desktop without disturbing unrelated containers. If compatible, reuse it. If outside the tested range, explain the issue and offer user-initiated upgrade or cancel. If absent, download from the approved official URL, validate signature/hash, show applicable terms, install with the WSL2 backend, start it, and wait on bounded readiness probes with progress.

Exit gate: absent/current/outdated Docker cases pass; no path automatically upgrades or resets Docker; unrelated containers remain unchanged.

### Phase 5 — Configuration, state, and secrets

Build screens for ERPNext version, validated site name, admin password with strength rules, web port, backup location, and optional WSL resource settings. Add the versioned atomic state store, DPAPI secret store, resume routing, and full log redaction tests.

Exit gate: kill the process after every state write and verify correct recovery; scan state, logs, crash files, process arguments, and generated configs for test secrets.

### Phase 6 — Container provisioning

Generate instance-scoped Compose/runtime files from the catalog, create volumes and backup bind directory, pull by digest with progress, start infrastructure, wait for MariaDB health, run the one-shot site creation/ERPNext install, explicitly enable the scheduler, start long-running services, and perform completion probes.

Exit gate: fresh v15 and v16 installs pass twice; an interruption at every substage resumes without duplicate site creation or data loss; database/Redis ports are not reachable from the host network.

### Phase 7 — Operations, backup, restore, and retention

Implement Manager actions and a daily Windows Scheduled Task. Backup runs:

```text
bench --site <site> backup --with-files --compress
```

It writes into a per-run staging directory on the host bind, verifies the expected database, config, public-file, and private-file artifacts are stable and non-empty, then atomically marks/moves the set as complete. Retention groups files by timestamp/run manifest, ignores staging/incomplete sets, removes complete sets older than 360 hours, and always retains the newest successful set.

Add a guided restore action even though the original specification names only backup; a backup that cannot be routinely restored is not an acceptable recovery feature. Restore requires a safety backup when possible, stops application workers, restores the chosen set, migrates/clears cache as required by the pinned release, and reruns health checks.

Exit gate: automated backup/restore round-trip validates sample records plus public/private attachments; Reset leaves all backups intact.

### Phase 8 — Disk monitoring and consent-based compaction

Record baseline disk locations and capacities, monitor free space/VHD usage, and warn at the equivalent of 80% of the 45 GB planning baseline (36 GB consumed) plus a critical free-space threshold. Do not enable experimental `sparseVhd`.

The monthly task only launches a consent prompt. On approval it checks for a recent successful backup, warns about all WSL distributions being stopped, stops the ERPNext stack cleanly, runs `wsl --shutdown`, confirms the target VHD is detached, uses the supported `Optimize-VHD` path or a validated `diskpart compact vdisk` fallback, then restarts and verifies ERPNext. On skip, record only the next prompt date.

Exit gate: skip makes no system change; cancellation/failure at each operation leaves a recoverable stack; the code never guesses a VHD path.

### Phase 9 — Repair, Reset, diagnostics, and UX completion

Implement existing-install detection through state plus Docker labels, Resume/Repair/Reset/Cancel, desktop/start-menu shortcuts, tray actions, browser launch, stage-specific friendly errors, copyable support IDs, and a diagnostics bundle that excludes secrets and business data by default.

Exit gate: Repair preserves a seeded database and attachments; Reset deletes only the chosen instance and keeps backups/unrelated Docker resources; malformed or foreign Docker resources are never adopted or deleted.

### Phase 10 — Packaging, hardening, and pilot

Package the self-contained application, add EULA/licensing screens, inventory third-party notices, run dependency/container vulnerability scans, execute the full clean-machine matrix, and conduct a small controlled pilot. Code signing remains optional only for the initial controlled rollout; make it a mandatory release gate before broad distribution.

Exit gate: release checklist signed, rollback tested, known limitations displayed, and support/runbook owners assigned.

## 7. Delivery sequence and dependencies

```text
Legal/version gates
  -> skeleton
  -> pre-flight
  -> WSL/reboot
  -> Docker
  -> state/secrets
  -> provisioning
  -> operations/backup/restore
  -> compaction
  -> repair/reset/UX
  -> packaging/pilot
```

For planning purposes, expect approximately 14–18 engineering weeks for one experienced Windows/.NET engineer, or 8–11 weeks for two engineers with shared Windows/Docker test infrastructure. This is a planning range, not a delivery commitment; Docker installation behavior, compaction safety, and clean-machine test automation are the largest uncertainties.

## 8. Definition of done for each stage

No stage is complete until it has:

- an explicit precondition and machine-verifiable postcondition;
- idempotent retry behavior;
- cancellation behavior;
- timeout and process-exit handling;
- a stable user-facing error/support code;
- redacted structured logs;
- unit tests for decision logic;
- integration or E2E coverage for the success path and at least one failure path; and
- cleanup rules that cannot target resources outside the current instance.

## 9. Acceptance test matrix

Minimum test coverage before release:

| Area | Required scenarios |
|---|---|
| OS/hardware | Minimum supported Windows 10; current Windows 11; Home/Pro where supported; unsupported build; x86/ARM block; virtualization disabled; 4/8/16 GB RAM; 19/20/44/45+ GB free. |
| WSL | Missing features; old WSL; functional WSL2; policy denial; Restart Now; Restart Later; relaunch token invalid; unrelated distro running. |
| Docker | Missing; compatible; outdated; engine stopped; Windows-container mode; unrelated containers/images/volumes present; registry unavailable; corrupt/partial download. |
| Networking | Selected port free/in use; firewall profiles; DNS failure; TLS failure; VPN/proxy detected; DB/Redis confirmed unpublished. |
| Versions | Fresh install and operation for every exact v15/v16 catalog entry. |
| Resumption | Forced close/power interruption before and after every state transition; corrupt primary state with valid backup state. |
| Data safety | Resume/Repair/Reset/Cancel; wrong-instance labels; final-backup failure; backup directory read-only/full; unrelated Compose project present. |
| Backup | Daily trigger; complete and incomplete sets; 15-day boundary; newest backup older than retention; attachments; restore round-trip. |
| Compaction | Skip; approve; no recent backup; VHD attached; insufficient privilege; Optimize-VHD unavailable; diskpart fallback; restart verification. |
| Security | Password policy; secret scanning; ACL checks; command injection through site/path fields; malicious state file; image digest enforcement; non-root containers where supported. |
| UX/support | Plain-language errors; keyboard navigation; high DPI; reboot resume; browser/shortcut/tray; diagnostics bundle contains no secrets or customer records. |

Use disposable physical/virtual Windows test machines with nested virtualization where supported. Keep at least one physical Windows 10 and one physical Windows 11 machine in the release qualification pool because WSL, firmware virtualization, UAC, and reboot behavior cannot be fully validated with unit tests.

## 10. Requirement traceability

| Spec section | Covered by |
|---|---|
| 1. Purpose and scope | Sections 1, 3, 9 |
| 2. Licensing | Sections 2, 6 Phase 0, Phase 10 |
| 3. Pre-flight checks | Section 6 Phase 2, section 9 |
| 4. Windows feature enablement | Section 4, section 6 Phase 3 |
| 5. Docker architecture | Sections 2, 3, 5 |
| 6. Resumable installation flow | Sections 4 and 6 Phases 3–9 |
| 7. Database readiness | Section 5 and Phase 6 |
| 8. Storage and disk management | Section 6 Phase 8 |
| 9. Backup strategy | Section 6 Phase 7 |
| 10. Security | Sections 3.3, 5, Phases 5/6/10 |
| 11. Error handling and logging | Sections 4, 6 Phase 9, section 8 |
| 12. Out of scope | Section 11 below |
| 13. Known risks | Sections 2, 6 Phase 0, section 12 below |

## 11. Explicit v1 exclusions

- corporate proxy/VPN support beyond detection and a clear message;
- offsite/cloud backup;
- HTTPS certificates and non-local network exposure;
- setup-wizard automation;
- multiple sites/tenants;
- Docker Engine-only deployment;
- ARM64 and Windows Server;
- unattended/silent provisioning; and
- automatic ERPNext major/minor upgrades after installation.

## 12. Risk register and mitigations

| Risk | Mitigation / gate |
|---|---|
| Docker licensing or redistribution terms change | Legal review and EULA check per release; download from Docker rather than rebundling unless redistribution is approved. |
| ERPNext/Docker compatibility drifts | Immutable release catalog, digest pinning, per-version contract tests, no `latest` tags. |
| WSL/Docker update breaks a working site | Tested Docker version range; warn before upgrade; Repair never auto-upgrades. |
| Local disk failure destroys live data and local backups | Prominent first-run warning; make backup folder selectable; recommend customer-managed external backup while cloud backup remains out of scope. |
| Reset deletes the wrong data | Unique instance IDs and labels, exact whitelists, dry-run summary, two confirmations, final backup offer, destructive-path tests. |
| Compaction impacts unrelated WSL workloads | Explicit all-WSL warning and consent, recent-backup check, clean stop, bounded recovery, skip by default. |
| Secrets leak through subprocesses/logs | DPAPI, stdin/secret-file transport, argument avoidance, centralized redaction, automated secret scans. |
| Unsupported proxy blocks installation | Detect early and fail with a named v1 limitation before making installation changes. |
| Unsigned installer produces trust warnings | Accept only for controlled pilot; require code signing before general distribution. |

## 13. First implementation checkpoint

Before building the full UI, deliver a console-based vertical slice that uses the same Core/Windows/Docker libraries to:

1. run pre-flight checks on one supported clean machine;
2. enable WSL features and resume after a reboot;
3. provision one pinned ERPNext v15 site;
4. create and restore one complete backup; and
5. prove that Repair preserves data and Reset preserves backups.

This checkpoint retires the highest technical risks before substantial wizard and packaging work begins. After it passes, build the WPF workflow over the already tested orchestration APIs.
