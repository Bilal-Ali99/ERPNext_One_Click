# Docker Desktop setup

## Who should use this guide

Use this guide when installing ERPNext Windows Installer as a Windows
administrator. ERPNext runs in Linux containers inside Docker Desktop; it does
not install its Linux services directly on Windows.

## Choose a Docker Desktop option

The installer asks how to handle Docker Desktop.

1. Choose **Use my existing Docker Desktop installation** when Docker Desktop
   is already installed.
2. Choose **Download and install the approved Docker Desktop release for all
   users** only when Docker Desktop is not installed and you authorize the
   download.

The installer uses a pinned official Docker Desktop release, verifies its
SHA-256 checksum and Windows signature, and installs it for all Windows users.
It does not automatically upgrade, reinstall, start, stop, or repair an
existing Docker Desktop installation. If Windows first needs to restart for
WSL setup, the choice to download Docker Desktop is retained when installation
resumes.

## After Docker Desktop is installed

1. Start **Docker Desktop** from the Windows Start menu.
2. Read and accept Docker's Subscription Service Agreement when Docker Desktop
   displays it.
3. Wait until Docker Desktop reports that its engine is running.
4. Ensure Docker Desktop is using **Linux containers**, not Windows containers.
5. Run the ERPNext installer again to continue setup.

## Troubleshooting

- If Docker Desktop is already installed but not running, start it and wait for
  the engine before running the ERPNext installer again.
- If it is set to Windows containers, switch it to Linux containers in Docker
  Desktop, then rerun the ERPNext installer.
- If the download or checksum verification fails, do not use that file. Check
  your network connection and contact the installer maintainer.

## Notes

Docker Desktop has its own licensing terms. The installer does not accept its
license on your behalf. Docker's official Windows installation guide documents
the all-user installation model and WSL 2 backend requirements:
<https://docs.docker.com/desktop/setup/install/windows-install/>.
