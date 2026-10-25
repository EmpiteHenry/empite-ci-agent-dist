# empite-ci-agent — releases

Release binaries and installers for the [Empite CI](https://github.com/empite/empite-ci)
build agent. Source lives in `empite/empite-ci-agent`; this repo only holds
releases and the installer scripts.

## Install

Linux / macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/bootstrap.sh | bash
```

Windows (elevated PowerShell):

```powershell
irm https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/install.ps1 | iex
```

Non-interactive: set `EMPITE_SERVER`, `EMPITE_ENROLL_TOKEN` (or `EMPITE_AGENT_SECRET`)
and `ASSUME_YES=1`; pin a release with `VERSION=v0.1.0`.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/uninstall.sh | bash -s -- --purge
```

```powershell
irm https://raw.githubusercontent.com/EmpiteHenry/empite-ci-agent-dist/main/uninstall.ps1 | iex
```

## Manual download

Every release has `empite-ci-agent-<version>-<os>-<arch>.zip` for linux/amd64,
linux/arm64, darwin/amd64, darwin/arm64 and windows/amd64, also reachable
without a version at
`https://github.com/EmpiteHenry/empite-ci-agent-dist/releases/latest/download/empite-ci-agent-<os>-<arch>.zip`.
Each zip contains the binary, the installer and `INSTALL.md`.
