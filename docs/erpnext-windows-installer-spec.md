# ERPNext / Frappe Windows Installer — Technical Specification

**Version 1.0**

## 1. Purpose & Scope

A Windows `.exe` installer that deploys ERPNext/Frappe via Docker, so the host
machine only needs Docker Desktop (WSL2 backend): no direct Node.js, Python,
Redis, or MariaDB installation on Windows itself. All application dependencies
are containerized and version-pinned to the selected ERPNext release.

**Target audience:** SMEs with under 100 employees and under $10M annual
revenue. **Platform:** Windows 10 (build 19041/2004+) or Windows 11 only. No
Linux/macOS support in v1.

## 2. Licensing

- Docker Desktop's free tier applies to organizations under 250 employees **and**
  under $10M revenue — both conditions must hold. This installer's target SME
  segment qualifies.
- Document this threshold explicitly in the EULA/customer-facing terms: if a
  customer's organization exceeds either threshold, licensing Docker Desktop
  becomes **their** responsibility, not the vendor's.
- Revisit this if the product is sold beyond the SME segment. A Docker
  Engine-only build would remove the Docker Desktop licensing question.

## 3. Pre-Flight Checks (Host Machine)

Run before any installation step. Hard blockers stop the installer with a clear
message; soft warnings are shown but do not block.

| Check | Type | Action |
| --- | --- | --- |
| Windows version/build | Hard blocker | Unsupported: clear error and stop |
| Admin/elevated privileges | Hard blocker | Prompt UAC elevation |
| Virtualization (VT-x/AMD-V) enabled in firmware | Hard blocker | Clear remediation and stop |
| Group Policy blocking Hyper-V/WSL | Hard blocker | Detect and show clear error |
| Free disk space | Hard blocker | Recommend 45 GB; hard minimum 20 GB |
| RAM | Soft warning | Recommend 8 GB+ |
| Internet connectivity | Hard blocker | Required for image pulls |
| Port availability (8000, 3306, 6379, 80/443) | Soft warning | Detect and report conflicts |
| Windows Firewall status | Soft warning | Check and explain possible Docker-networking blocks |
| Existing Docker Desktop install | Soft warning | Detect version; offer, never force, an upgrade |
| Corporate proxy/VPN | Out of scope v1 | Documented unsupported limitation |

## 4. Windows Feature Enablement (Hyper-V/WSL2)

**Principle: never force a restart without explicit user consent.**

1. Detect whether Hyper-V, Virtual Machine Platform, and WSL2 are enabled.
2. If needed, enable them through an elevated PowerShell/DISM script.
3. Persist installer state with `{"stage":"features_enabled_pending_restart"}`.
4. Offer **Restart Now** and **Restart Later**. Both actions are user initiated.
5. Register a Scheduled Task or Registry `Run` key that relaunches the installer
   after the next login.
6. On relaunch, read state, confirm WSL2 works, and resume at Docker setup.

## 5. Docker Architecture

- Use **Docker Desktop with the WSL2 backend**.
- Follow official `frappe_docker` conventions:
  - Use separate `redis-cache` and `redis-queue` containers, with
    `redis_cache`, `redis_queue`, and `redis_socketio` in
    `common_site_config.json`.
  - Use `backend`, `frontend`, `db`, `redis-cache`, `redis-queue`, `scheduler`,
    `queue-worker`, and `websocket` services.

| ERPNext Version | Base OS | Python | Node.js |
| --- | --- | --- | --- |
| v15 | Ubuntu 22.04 | 3.10 / 3.11 | 18 / 20 |
| v16 | Ubuntu 24.04 recommended, or 22.04 with manual Python 3.12 | 3.12+ | 22+ |

MariaDB and Redis versions are pinned to the requirements of the selected
ERPNext release, rather than selected independently.

## 6. Installation Flow (Resumable State Machine)

Every stage writes completion to persistent state so the installer resumes after
a crash, reboot, or manual close rather than restarting from zero.

1. Launch installer and request elevation.
2. Run pre-flight checks.
3. Enable Hyper-V/WSL2 if necessary, using the consent-based restart flow.
4. Detect or install Docker Desktop.
5. Prompt for ERPNext version, site name, user-supplied admin password, and
   optional WSL2 memory/processors.
6. Detect existing volumes/containers. Offer **Resume**, **Repair**, **Reset**
   (double confirmation), or **Cancel**; never silently wipe data.
7. Pull/build the selected containers and create persistent DB/site volumes plus
   a host-mounted backup folder outside those volumes.
8. Wait for the MariaDB health check.
9. Run `bench new-site`, `bench get-app erpnext`, `bench install-app erpnext`,
   and `bench enable-scheduler`.
10. Configure daily backup.
11. Configure consent-based monthly storage compaction.
12. Launch the browser, create start/stop desktop and tray integration, and log
    completion.

## 7. Database Readiness (Race-Condition Fix)

`bench new-site` must not run before MariaDB initialization finishes. Use a
Docker Compose MariaDB health check (for example, `mysqladmin ping`) and
`depends_on: condition: service_healthy` on the backend. Do not use a fixed
sleep timer.

## 8. Storage & Disk Management

- Do not artificially cap disk size. Check free space before installation and
  let the database grow naturally.
- Do not enable WSL2's experimental `sparseVhd` setting; it is unreliable and
  can create data-corruption risk for this workload.
- Warn users when backup/VHD usage reaches approximately 80% of the 45 GB
  baseline.
- Provide a monthly, consent-gated compaction task using `wsl --shutdown` and
  `Optimize-VHD` or `diskpart compact vdisk`. It must never run silently.

## 9. Backup Strategy

- Run every 24 hours with `bench backup --with-files --compress`.
- Store output in a host bind-mounted folder outside Docker-managed volumes so
  Reset cannot destroy backups.
- Group timestamp-prefixed database/config/public/private files into complete,
  stable backup sets before cleanup.
- Delete complete sets older than 360 hours (15 days), but always retain the
  newest successful set.
- Offsite/cloud backup is deferred from v1.

## 10. Security

- The admin password is user supplied; enforce basic strength rules and never
  log it in plaintext.
- MariaDB and Redis stay on the internal Docker network, without host port
  mappings.
- Run containers as non-root wherever the image supports it.

## 11. Error Handling & Logging

- Persist state at every stage so installation resumes after failure.
- Store diagnostics in a fixed, discoverable local log location.
- Show a clear failed-stage message to users; raw stack traces belong only in
  the diagnostic log.

## 12. Out of Scope for v1

- Corporate proxy/VPN passthrough.
- Offsite/cloud backup integration.
- SSL/HTTPS for local access.
- Automation of the ERPNext setup wizard.
- Multi-site/multi-tenant support.
- Code signing of the `.exe` for the current single-client rollout.

## 13. Known Risks to Revisit

- Docker Desktop licensing if the product expands beyond the SME target segment.
- Lack of proxy support on networks that enforce one.
- Local backup and live data can both be lost in a physical-disk failure unless
  the customer backs up the host-mounted folder externally.
