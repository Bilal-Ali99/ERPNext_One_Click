# Windows feature restart and resume

## Audience and prerequisites

This applies to an administrator installing ERPNext Windows Installer on a
supported Windows 10 or Windows 11 computer. The installer must be run with
administrator privileges. Save work in other applications before choosing a
restart.

## What happens when Windows features are missing

The installer checks whether **Windows Subsystem for Linux** and **Virtual
Machine Platform** are available. If either feature is missing, it enables only
the missing feature and asks you to choose one of these actions:

1. **Restart Now** — Windows restarts only after you select this option.
2. **Restart Later** — no restart occurs. Restart Windows yourself when ready.

No restart is performed without one of those explicit choices.

## After restarting

1. Sign in using the same Windows account that started the installer.
2. The installer resumes automatically at sign-in.
3. It verifies that WSL is working before continuing with Docker setup.

If WSL is not ready yet, the installer stays at the restart/resume step rather
than continuing with a partly configured installation. Restart Windows again
or contact your IT administrator if the condition persists.

## Safety note

Do not run `enable-features.ps1` directly. Use the installer wizard so the
installation state and restart/resume information remain consistent.
