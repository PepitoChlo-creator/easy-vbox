# Security policy

EasyVbox is a bash wrapper around `VBoxManage`. It runs on your machine, with
your privileges, so a bug here can matter even though the project is small.

## Supported versions

Only the latest release gets fixes. `main` is the development branch.

| Version | Supported |
|---|---|
| 3.2.x | ✅ |
| 3.1.x and older | ❌ (upgrade; the 3.1.0 tarball cannot download ISOs) |

Check what you run with `./scripts/create-vm.sh --version`.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private reporting:

<https://github.com/PepitoChlo-creator/easy-vbox/security/advisories/new>

If that page says private reporting is not enabled for this repository, open a
public issue with **no details** — just "security report, please contact me" —
and a maintainer will open a private channel. Do not describe the bug publicly
until a fix ships.

Please include: the version, your host OS and VirtualBox version, the exact
command, and what you expected versus what happened. If the problem is in a log
or a dry-run plan, paste it — but **redact passwords first**.

This is a volunteer project: expect an acknowledgement within about a week and
a best-effort fix. There is no bug bounty.

## In scope

Anything where the scripts themselves weaken your machine or your data:

- **Command injection** through values that reach `VBoxManage` (VM name, shared
  folder path, port-forward spec, preset name, provisioning file).
- **Secret leakage**: a password appearing in a log file, a dry-run plan,
  `--print-config` output, or a shell trace.
- **Checksum bypass** in `--download`: using a file whose SHA-256 does not match
  the upstream list, or silently skipping verification.
- **Unsafe file handling**: writing outside the documented cache/log
  directories, predictable temporary files, following symlinks destructively.
- **Destructive operations without confirmation** (`--delete-vm`, `--replace`)
  acting on the wrong VM.

## Out of scope

- Vulnerabilities in **VirtualBox itself** or in the Extension Pack — those go
  to [Oracle](https://www.virtualbox.org/wiki/Security). Report them upstream.
- Bugs in a guest OS, or in an image you downloaded and installed.
- A malicious ISO you chose to boot; EasyVbox verifies published checksums but
  cannot certify third-party images.
- `--password` being visible in `ps` output. That is inherent to command-line
  arguments: use the `EASYVBOX_PASSWORD` environment variable or let EasyVbox
  generate one, both of which keep the secret out of the process list.
- Running the scripts as root or with `sudo` (not supported, see
  [`docs/INSTALL.md`](docs/INSTALL.md)).

## What EasyVbox already does

- Redacts the guest password from logs and dry-run plans (`redact()` in
  `scripts/create-vm.sh`).
- Refuses `--delete-vm` for a running VM and requires the VM name typed out,
  or an explicit `--yes`, before deleting anything.
- Verifies downloaded ISOs against the upstream `SHA256SUMS` file and deletes
  the file on mismatch.
- Writes logs under `~/.easyvbox/logs` unless you point them elsewhere.
