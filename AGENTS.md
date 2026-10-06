# Repository Instructions

For every non-trivial task in this repository, read and follow
`.codex/workflows/task-workflow.md` before making implementation changes.

A task is non-trivial when it requires investigation, affects more than one
file or behavior, changes architecture/data/security, or needs meaningful
verification. One-line edits and simple factual questions do not require the
workflow.

Store durable working notes for active tasks in `.codex/tasks/<slug>/` as
described by the workflow. These notes are scratch state, not product
documentation.

The user's current request and higher-priority Codex instructions override the
workflow when they conflict. Do not let workflow bookkeeping delay useful work
or create an approval gate the user did not request.

# AGENTS.md — ERPNext/Frappe Windows Installer

This file instructs any coding agent (Claude Code, Codex, Cursor, etc.) working in this repository. Read this fully before writing or modifying any code. It encodes decisions finalized across a multi-round requirements review — do not silently deviate from them without flagging the deviation to the human maintainer.

---

## 1. Project Overview

**What this project builds:** A Windows `.exe` installer that deploys a fully working ERPNext/Frappe instance on a Windows machine, using Docker (WSL2 backend) for isolation. The host machine never gets Node.js, Python, Redis, or MariaDB installed directly — only Docker Desktop and the Windows Subsystem for Linux.

**Target user:** Non-expert-but-technically-comfortable staff at SMEs (under 100 employees, under $10M revenue). Assume they can click through a wizard and follow plain-English instructions, but cannot troubleshoot Docker/WSL internals themselves.

**Platform:** Windows 10 (build 19041 / 2004 or later) and Windows 11 only. No Linux/macOS installer in this phase.

**Full product spec:** `docs/erpnext-windows-installer-spec.md` (the finalized requirements document this AGENTS.md implements). If anything here and that doc conflict, the spec doc is the source of truth for *what* to build; this file governs *how* to build it.

---

## 2. Assumed Tech Stack (stated explicitly — flag to maintainer before changing)

| Layer | Choice | Why |
|---|---|---|
| Installer wrapper (.exe) | **Inno Setup** | Free, mature, supports custom wizard pages, elevation, and running bundled scripts |
| Host-side orchestration | **PowerShell 5.1+ (compatible with 7)** | Native to Windows; required for DISM, WSL, registry, and Scheduled Task operations — no extra runtime to bundle |
| Containers | **Docker Desktop, WSL2 backend** | Per spec §5/§2 |
| Container orchestration | **Docker Compose**, modeled on official `frappe_docker` conventions | Inherits tested compatibility instead of reinventing it |
| State persistence | JSON file on disk | Simple, human-readable, easy to debug/support |

Do not introduce Python, Node, or any other host-side runtime dependency purely for the installer's own orchestration logic — that would reintroduce the exact host-pollution problem this project exists to avoid. Python/Node inside the *containers* is fine and expected.

---

## 3. Repository Structure

```
erpnext-windows-installer/
├── AGENTS.md
├── README.md
├── docs/
│   └── erpnext-windows-installer-spec.md
├── installer/
│   ├── setup.iss                      # Inno Setup script — compiles the final .exe
│   ├── assets/                        # icons, wizard banner images
│   └── scripts/
│       ├── orchestrate.ps1            # main state-machine driver, entry point
│       ├── preflight.ps1
│       ├── enable-features.ps1
│       ├── install-docker.ps1
│       ├── collect-user-input.ps1
│       ├── provision-containers.ps1
│       ├── setup-site.ps1
│       ├── configure-backups.ps1
│       ├── configure-compaction.ps1
│       ├── backup.ps1                 # run on schedule
│       ├── cleanup-backups.ps1        # run on schedule
│       ├── compact-storage.ps1        # run on schedule, consent-gated
│       └── common/
│           ├── Logging.psm1
│           ├── StateManager.psm1
│           └── Utils.psm1
├── docker/
│   ├── docker-compose.v15.yml
│   ├── docker-compose.v16.yml
│   ├── .env.template
│   └── config/
│       └── common_site_config.template.json
└── tests/
    ├── Preflight.Tests.ps1
    ├── StateManager.Tests.ps1
    └── BackupCleanup.Tests.ps1
```

---

## 4. Build / Test / Run Commands

- **Compile installer:** open `installer/setup.iss` in Inno Setup Compiler, or run `iscc installer/setup.iss` from CLI.
- **Run PowerShell unit tests:** `Invoke-Pester ./tests/` (Pester module required).
- **Manually test a single stage without running the full installer:** each script in `installer/scripts/` must be independently runnable and idempotent, e.g. `./installer/scripts/preflight.ps1 -WhatIf` for a dry run.
- **Never test destructive stages (Reset, container teardown) against a machine with real customer data.** Use a disposable VM or Windows Sandbox.

---

## 5. Global Constants (use these exact values/paths everywhere — do not invent alternates)

```powershell
$AppName        = "ERPNextWindowsInstaller"
$StateFilePath  = "$env:LOCALAPPDATA\$AppName\state.json"
$LogDirectory   = "$env:LOCALAPPDATA\$AppName\logs"
$LogFilePath    = "$LogDirectory\install.log"
$BackupRoot     = "$env:USERPROFILE\ERPNext-Backups"   # host-mounted, OUTSIDE Docker volumes
$DockerNetwork  = "erpnext_network"
$DbVolumeName   = "erpnext_db_data"
$SitesVolumeName = "erpnext_sites"
$DefaultSitePort = 8000      # the ONLY container port published to the host
```

MariaDB (3306) and Redis (6379) ports are **never** published to the host — they stay on `erpnext_network` only, per the security requirement in §10 of the spec. Do not add `ports:` mappings for them in docker-compose. This also means the pre-flight port-conflict check only needs to verify `$DefaultSitePort` (and the websocket port if separately exposed) is free — not 3306/6379.

---

## 6. Installation State Machine

This is the backbone of the whole installer. Every stage below **must** write its completion to `$StateFilePath` before moving to the next, so a crash, reboot, or manual close can resume exactly where it left off — never restart the whole flow from zero.

### State file schema

```json
{
  "stage": "FEATURES_ENABLED_PENDING_RESTART",
  "erpnext_version": "v16",
  "site_name": "",
  "wsl_memory": "6GB",
  "wsl_processors": 2,
  "last_updated": "ISO-8601 timestamp"
}
```

### Stage enum (implement as a PowerShell enum or constant list in `StateManager.psm1`)

```
NOT_STARTED
PREFLIGHT_DONE
FEATURES_ENABLED_PENDING_RESTART
FEATURES_CONFIRMED
DOCKER_READY
USER_INPUT_COLLECTED
EXISTING_INSTALL_RESOLVED
CONTAINERS_PROVISIONED
DB_HEALTHY
SITE_CREATED
BACKUP_CONFIGURED
COMPACTION_SCHEDULED
COMPLETE
```

### Flow detail

**Stage: PREFLIGHT_DONE**
Run `preflight.ps1`. See §7 for exact checks. Hard blockers abort with a clear, plain-English message (no raw PowerShell errors shown to the user — log the raw error, show a friendly summary). Soft warnings are shown but don't block.

**Stage: FEATURES_ENABLED_PENDING_RESTART → FEATURES_CONFIRMED**
See §8. **Critical rule: never call `Restart-Computer` automatically.** Always show a dialog with "Restart Now" / "Restart Later" — both user-initiated. Register a Scheduled Task (`Register-ScheduledTask`, trigger `AtLogOn`) that relaunches `orchestrate.ps1`, which reads the state file and resumes at `FEATURES_CONFIRMED` once it verifies WSL2 is functional (`wsl --status` returns successfully).

**Stage: DOCKER_READY**
Detect Docker Desktop via `Get-Command docker -ErrorAction SilentlyContinue` plus `docker version`. If absent, install silently via the official Docker Desktop installer executable bundled or downloaded. If present but outdated, **warn and let the user choose** whether to upgrade — do not auto-upgrade, since the user may have other projects depending on their current Docker Desktop version/config.

**Stage: USER_INPUT_COLLECTED**
Collect via wizard pages (see §9 for field-level rules):
- ERPNext version (v15 / v16)
- Site name
- Admin password (user-typed, validated, never auto-generated)
- WSL2 resource allocation (memory/processors) — present sensible defaults, let user override

**Stage: EXISTING_INSTALL_RESOLVED**
Check for pre-existing volumes/containers matching `$DbVolumeName`/`$SitesVolumeName`/`$DockerNetwork`. If found, present exactly these four choices — never auto-wipe:
- **Resume** — continue an interrupted install using existing state
- **Repair** — attempt to fix a broken install without touching data
- **Reset** — destroy and recreate (require a typed confirmation, e.g. the user must type the site name, before proceeding)
- **Cancel**

**Stage: CONTAINERS_PROVISIONED**
Run `docker compose -f docker/docker-compose.<version>.yml up -d` using the version selected in `USER_INPUT_COLLECTED`. See §11 for compose file requirements.

**Stage: DB_HEALTHY**
Do not proceed until the MariaDB healthcheck passes. See §12 — this is the fix for the known race-condition failure mode. Never use a fixed `Start-Sleep` as a substitute.

**Stage: SITE_CREATED**
Exact `bench` command sequence (run via `docker compose exec backend ...`):
```
bench new-site <site_name> --admin-password <user_supplied_password> --mariadb-root-password <generated_root_pw>
bench --site <site_name> get-app erpnext
bench --site <site_name> install-app erpnext
bench --site <site_name> enable-scheduler
```
Do not skip `enable-scheduler` — without it, background jobs (emails, recurring tasks) silently never run.

**Stage: BACKUP_CONFIGURED**
See §13.

**Stage: COMPACTION_SCHEDULED**
See §14.

**Stage: COMPLETE**
Auto-launch default browser to `http://localhost:$DefaultSitePort`. Create a desktop shortcut and system tray icon for start/stop. Write a final success entry to the log.

---

## 7. Pre-Flight Checks — Exact Implementation

| Check | PowerShell approach | Type |
|---|---|---|
| Windows version | `[System.Environment]::OSVersion.Version` ≥ 10.0.19041 | Hard blocker |
| Admin privileges | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)` | Hard blocker |
| Virtualization enabled | `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` or `(Get-ComputerInfo).HyperVisorPresent` | Hard blocker |
| Hyper-V/WSL blocked by Group Policy | Catch the specific error code from `Enable-WindowsOptionalFeature` when attempted; detect policy restriction, not a generic failure | Hard blocker |
| Free disk space | `(Get-PSDrive C).Free` — require ≥ 45GB recommended, 20GB hard minimum | Hard blocker |
| RAM | `(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory` — warn if < 8GB | Soft warning |
| Internet connectivity | `Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet` or an actual HTTPS reachability check to Docker Hub | Hard blocker |
| Port availability | `Test-NetConnection -ComputerName localhost -Port $DefaultSitePort` — only check `$DefaultSitePort` (see §5 on why 3306/6379 aren't checked) | Soft warning |
| Windows Firewall status | `Get-NetFirewallProfile` — always check, never assume it's off | Soft warning |
| Existing Docker Desktop | `docker version --format '{{.Server.Version}}'` | Soft warning |
| Corporate proxy | **Not implemented in v1** — do not add proxy-detection logic; if a future task asks for it, treat it as a new feature, not a bug fix | Out of scope |

---

## 8. Windows Feature Enablement — Exact Implementation

```powershell
# Check
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
$vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

if ($wslFeature.State -ne 'Enabled' -or $vmpFeature.State -ne 'Enabled') {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    # Always pass -NoRestart. The installer controls when the user is asked, never Windows.
    Set-InstallState -Stage "FEATURES_ENABLED_PENDING_RESTART"
    Show-RestartPrompt   # custom function: dialog with Restart Now / Restart Later, both user-driven
}
```

On relaunch after restart, verify with `wsl --status` before advancing the stage. Never assume success just because the reboot happened.

---

## 9. User Input Field Rules

- **ERPNext version:** radio choice, v15 or v16 only. Selecting this determines the compose file used (§11) — do not let the user separately pick an Ubuntu version; it's derived from the ERPNext version choice automatically.
- **Site name:** validate as a valid hostname-like string; no spaces or special characters.
- **Admin password:** user-typed, with a masked input + confirm field. Enforce minimum length (12+ characters recommended) and basic complexity. **Never auto-generate this password.** Never log it in plaintext anywhere, including debug logs — mask it in all log output (`********`).
- **WSL2 resource allocation:** present defaults of `memory=6GB`, `processors=2`, editable by the user. Write the chosen values to `%USERPROFILE%\.wslconfig` under `[wsl2]`. Do not attempt to set any disk-size-related key in `.wslconfig` — no such setting exists (see §14 for why).

---

## 10. Security Checklist (verify all of these before marking a build release-ready)

- [ ] MariaDB and Redis have no `ports:` mapping in docker-compose — internal network only.
- [ ] Admin password never appears in plaintext in any log file.
- [ ] Containers run as non-root where the base image supports a non-root user.
- [ ] `$BackupRoot` folder permissions are restricted to the installing user.
- [ ] No hardcoded credentials anywhere in scripts or compose files — generate the MariaDB root password randomly per-install and store it only in the state file (not in logs).

---

## 11. Docker Compose Requirements

Two compose files, `docker-compose.v15.yml` and `docker-compose.v16.yml`, following `frappe_docker` service conventions:

| Service | Role |
|---|---|
| `backend` | Frappe/bench application server |
| `frontend` | nginx reverse proxy — the **only** service with a published host port (`$DefaultSitePort`) |
| `db` | MariaDB |
| `redis-cache` | Redis, cache role only |
| `redis-queue` | Redis, queue + socketio role |
| `scheduler` | Runs `bench schedule` |
| `queue-worker` | Background job worker |
| `websocket` | Realtime updates |

Version matrix — base image selection is driven by the user's ERPNext version choice from §9:

| ERPNext Version | Base OS | Python | Node.js |
|---|---|---|---|
| v15 | Ubuntu 22.04 | 3.10 / 3.11 | 18 / 20 |
| v16 | Ubuntu 24.04 (default) or 22.04 + manual Python 3.12 | 3.12+ | 22+ |

`common_site_config.json` must explicitly set `redis_cache`, `redis_queue`, and `redis_socketio` to point at the two separate Redis services — do not collapse them into a single Redis container.

---

## 12. MariaDB Health Check (Race-Condition Fix)

```yaml
db:
  image: mariadb:<pinned-version>
  healthcheck:
    test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
    interval: 5s
    timeout: 5s
    retries: 12

backend:
  depends_on:
    db:
      condition: service_healthy
```

Do not replace this with a `Start-Sleep`/fixed-delay workaround anywhere in the orchestration scripts — this was an explicitly identified recurring failure mode in the design review and must stay solved at the compose level.

---

## 13. Backup Implementation

- **Command:** `docker compose exec backend bench --site <site_name> backup --with-files --compress`
- **Schedule:** every 24 hours via a Windows Scheduled Task calling `backup.ps1`.
- **Output location:** the backup command's output files must be copied/mounted to `$BackupRoot` (host-mounted, outside `$DbVolumeName`/`$SitesVolumeName`) — this is deliberate so a "Reset" in §6 never destroys existing backups.
- **Cleanup logic** (`cleanup-backups.ps1`), run after each successful backup:
  1. Group files in `$BackupRoot` by their `bench`-generated timestamp prefix into complete sets (db dump + site config + public/private tarballs).
  2. Skip any set that isn't fully written yet — check all expected files for that timestamp exist and are not still being modified (e.g. file handle not locked, modified time stable for at least a few minutes) before treating it as eligible.
  3. Delete complete sets older than 360 hours (15 days).
  4. **Always retain at least the single most recent successful backup set, regardless of its age** — this is a hard safety floor, not a suggestion.

---

## 14. Storage & Compaction Implementation

- Pre-flight requires 45GB free (§7) as the baseline — do not implement any artificial cap on how large the database/volumes are allowed to grow.
- **Do not enable WSL2's experimental `sparseVhd` setting.** It is documented as unreliable and flagged by Microsoft as a potential data-corruption risk for the exact kind of always-on database workload this product runs. This was a deliberate decision in the design review, not an oversight — do not "fix" this later by turning it on.
- Implement a disk-usage monitor that warns the user when `$BackupRoot` + the WSL2 VHDX combined usage crosses ~80% of the provisioned baseline (45GB, or whatever the pre-flight check used).
- **Monthly compaction task** (`compact-storage.ps1`), registered as a monthly Scheduled Task:
  ```powershell
  wsl --shutdown
  Optimize-VHD -Path <path-to-docker-desktop-data.vhdx> -Mode Full   # requires Hyper-V module
  ```
  This task **must always prompt the user first** ("Monthly storage optimization is ready to run — Run Now / Skip this month") — it is never silent or fully automatic, even though it's scheduled.

---

## 15. Logging Conventions

- All scripts import `common/Logging.psm1` and use a single `Write-InstallLog -Level <Info|Warning|Error> -Message <string>` function — no raw `Write-Host` for anything user-facing or diagnostic.
- Log format: `[ISO-8601 timestamp] [LEVEL] [stage-name] message`
- Log file: `$LogFilePath`, append mode, no rotation needed for v1 (files are small; revisit if this becomes an issue).
- Never log: admin password, MariaDB root password, or any other secret — mask with `********` if a value must be referenced in a log line.

---

## 16. Out of Scope — Do Not Implement Without Explicit Sign-Off

- Corporate proxy/VPN passthrough.
- Offsite/cloud backup upload (Frappe's S3 Backup Settings doctype) — placeholder only, not wired up.
- SSL/HTTPS for local access — plain HTTP on `$DefaultSitePort` is accepted for v1.
- Automated scripting of the ERPNext setup wizard (company name, chart of accounts) — the user fills this in manually on first browser load.
- Multi-site/multi-tenant support — one site per install.
- Code signing of the final `.exe` — recommended before any wide public distribution, but not required for the current single-client rollout. Flag this to the maintainer before the first external customer install.

---

## 17. Known Accepted Risks (do not "fix" silently — these were deliberate trade-offs)

- Docker Desktop's free-tier licensing applies as long as the customer stays under 250 employees and $10M revenue. If a future customer exceeds this, that's documented as their responsibility in the EULA, not something this codebase needs to detect or enforce.
- No proxy support means installs will fail on networks that enforce one — this is a known, accepted v1 limitation, not a bug.
- Backups living only in `$BackupRoot` on the same physical disk means a hardware failure still takes out both live data and backups — offsite backup is the eventual mitigation, deferred per §16.

---

## 18. Testing Requirements for Any PR

- Any change to `preflight.ps1`, `enable-features.ps1`, or the state machine must be tested on a disposable VM or Windows Sandbox snapshot — never on a machine with a real install.
- Test the full Resume / Repair / Reset / Cancel branch explicitly whenever touching `EXISTING_INSTALL_RESOLVED` logic — this is the highest-risk area for accidental data loss.
- Test `cleanup-backups.ps1` against a directory containing a deliberately incomplete/in-progress backup set to confirm it's correctly skipped, not deleted.
- Confirm the MariaDB healthcheck actually blocks `bench new-site` by testing against a deliberately slow-starting MariaDB container.