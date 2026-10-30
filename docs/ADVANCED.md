# Advanced usage

Everything the CLI can do, plus recipes for common setups.

## Full flag reference

`--opt value` and `--opt=value` are both accepted. Booleans have explicit
counterparts so a preset can always be overridden.

### General

| Flag | Description |
|---|---|
| `-h, --help` | Print help and exit |
| `-V, --version` | Print version and exit |
| `--list-presets` | List presets with specs and descriptions |
| `--list-vms` | List the VMs registered with VirtualBox |
| `--delete-vm NAME` | Unregister `NAME` and delete its disks |
| `--print-config` | Resolve preset + flags and print `key=value` lines |
| `-n, --dry-run` | Print the VBoxManage plan; modifies nothing |
| `-y, --yes` | Do not ask for confirmation (used by `--replace`) |
| `--log-file PATH` | Write the VBoxManage log to `PATH` |
| `--no-log` | Do not write a log file |
| `--no-verify` | Skip the post-creation configuration check |
| `--verify` | Force the check (default) |

### VM

| Flag | Description |
|---|---|
| `--iso PATH` | Installer image; `none` creates a VM without optical media |
| `--name NAME` | VM name; default is the ISO file name, sanitized |
| `--preset NAME` | Load `presets/NAME.json` |
| `--ostype TYPE` | Override the detected VirtualBox OS type (e.g. `Ubuntu_64`) |
| `--ram SIZE` | Memory; bare numbers are MiB, suffixes `K/M/G/T` work |
| `--cpus N` | Virtual CPUs |
| `--disk SIZE` | Disk size; same size syntax as `--ram` |
| `--vram N` | Video memory in MiB (4 – 256) |
| `--nvme`, `--no-nvme` | NVMe on PCIe (default) or SATA |
| `--3d`, `--no-3d` | Hardware 3D acceleration |
| `--graphics TYPE` | `vmsvga` (default), `vboxsvga` or `none` |
| `--firmware TYPE` | `efi` (default) or `bios` |
| `--nested`, `--no-nested` | Expose VT-x/AMD-V to the guest |
| `--usb MODE` | `off`, `ohci`, `ehci`, `xhci` (default on VirtualBox 7+, `ohci` before) |
| `--tpm TYPE` | `none` (default) or `2.0` |
| `--secure-boot on\|off` | UEFI Secure Boot (needs EFI, VirtualBox 7+) |
| `--machine-folder PATH` | Where the VM lives (default: VirtualBox's own default folder) |
| `--force-resources` | Keep requested RAM/CPUs even if they exceed host capacity |

### Startup

| Flag | Description |
|---|---|
| `--gui` | Start with a window (default) |
| `--headless` | Start without a window |
| `--no-start` | Create the VM and leave it powered off |
| `--replace` | Delete and recreate an existing VM (asks first) |

### Networking

| Flag | Description |
|---|---|
| `--network TYPE` | `nat` (default), `bridged`, `hostonly`, `intnet`, `none` |
| `--bridge-adapter NAME` | Bridged interface; auto-detected, `auto` forces detection |
| `--hostonly-adapter NAME` | Host-only interface; first available by default |
| `--intnet-name NAME` | Internal network name |
| `--ssh-port PORT` | Host port forwarded to guest port 22 (default `2222`, `none` disables) |
| `--forward SPEC` | `name:hostport:guestport`, repeatable |

### Sharing

| Flag | Description |
|---|---|
| `--shared-folder SPEC` | `[name=]PATH[:ro]` shared into the guest |
| `--shared-name NAME` | Share name when the spec has none (default `HostShare`) |

### Installer image and automation

| Flag | Description |
|---|---|
| `--download NAME\|URL` | Download the image (cached, checksum-verified) and use it |
| `--list-isos` | List the catalog entries and exit |
| `--iso-cache DIR` | Cache directory for downloaded images |
| `--unattended` | Let VirtualBox answer the installer (6.1+) |
| `--user NAME` | Guest user (default `vboxuser`) |
| `--password PASS` | Guest password; prefer `EASYVBOX_PASSWORD` |
| `--hostname NAME` | Guest hostname (default: the VM name) |
| `--locale SPEC` | Installer locale (default `en_US`) |
| `--country CODE` | Installer country (default `US`) |
| `--timezone TZ` | Guest time zone (default `UTC`) |
| `--install-additions`, `--no-install-additions` | Install Guest Additions (default: when the ISO is found) |
| `--provision FILE` | Run a shell script in the guest after installing (repeatable) |
| `--with-docker` | Install Docker and add the guest user to the `docker` group |

## Environment variables

| Variable | Effect |
|---|---|
| `VBOXMANAGE` | Path to `VBoxManage` (otherwise searched in PATH and common locations) |
| `EASYVBOX_LOG_DIR` | Directory for logs (default `~/.easyvbox/logs`) |
| `EASYVBOX_PRESETS_DIR` | Alternative preset directory |
| `EASYVBOX_HOST_RAM_MB` | Override detected host RAM (handy for tests/CI) |
| `EASYVBOX_HOST_CPUS` | Override detected host CPU count |
| `EASYVBOX_PASSWORD` | Guest password for `--unattended` (keeps it out of the command line) |
| `EASYVBOX_ISO_CACHE` | ISO cache directory |
| `EASYVBOX_ISO_CATALOG` | Alternative ISO catalog file |
| `EASYVBOX_DOWNLOADER` | Replace curl/wget when fetching images |
| `NO_COLOR` | Disable coloured output |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success (including `--dry-run`, `--help`, `--print-config`) |
| `1` | Runtime failure (VirtualBox error, VM exists, start failure) |
| `2` | Usage error (unknown option, bad value, missing ISO, unknown preset) |

## How resolution works

1. Command-line flags are parsed first and remembered.
2. A preset fills only the values you did not set — **flags always win**.
3. Remaining gaps get smart defaults derived from the host.
4. RAM/CPUs are clamped to `host RAM - 2048 MiB` and `host CPUs` unless
   `--force-resources` is given.
5. Windows 11 rules raise RAM/CPU/disk and force EFI, TPM 2.0 and Secure Boot.
6. Validation runs (ranges, enums, version requirements).

Inspect the result at any point with `--print-config`:

```bash
$ ./scripts/create-vm.sh --iso kali.iso --preset gaming --ram 8G --print-config
preset=gaming
ram_mb=8192
cpus=8
...
```

## Storage layout

- **Default (NVMe):** `NVMe` controller on PCIe with `--portcount 1`, disk at
  port 0. The installer ISO goes to a separate `SATA` controller (ports 0-2),
  because NVMe cannot carry optical media. Port 2 stays free for Guest
  Additions.
- **`--no-nvme`:** one `SATA` controller; disk at port 0, ISO at port 1, Guest
  Additions at port 2.
- Disks are dynamically allocated VDI (`--variant Standard`), so the file grows
  as the guest uses it.

## Recipes

### Headless server with SSH on a custom port

```bash
./scripts/create-vm.sh --iso ubuntu-server-24.04.iso --preset server \
  --name web01 --ssh-port 2201 --cpus 4 --ram 8G --no-start

VBoxManage startvm web01 --type headless
ssh -p 2201 user@localhost
```

### Development VM with a shared folder and extra ports

```bash
./scripts/create-vm.sh --iso ubuntu-24.04.iso --preset dev --name dev \
  --shared-folder code=~/src \
  --forward api:3000:3000 --forward db:5432:5432
```

Inside the guest (with Guest Additions):

```bash
sudo usermod -aG vboxsf "$USER"   # then log out and back in
ls /media/sf_code
```

### Windows 11

```bash
./scripts/create-vm.sh --iso ~/Downloads/Win11_24H2.iso --preset windows11 --name Win11
```

The preset sets EFI, TPM 2.0 and Secure Boot and enforces 8 GiB RAM / 4 CPUs /
128 GiB disk. If your build rejects `--secure-boot`, EasyVbox enrolls the NVRAM
keys instead and tells you.

> Windows 11 also checks the CPU model. If Setup complains, that is a guest
> requirement issue, not an EasyVbox one; see `docs/TROUBLESHOOTING.md`.

### Bridged networking on a specific interface

```bash
./scripts/create-vm.sh --iso debian.iso --network bridged --bridge-adapter enp3s0
```

Without `--bridge-adapter`, EasyVbox picks the interface of the default route
and tells you which one it used. List options with:

```bash
VBoxManage list bridgedifs | grep '^Name:'
```

### A blank VM (PXE, second disk, recovery)

```bash
./scripts/create-vm.sh --iso none --preset minimal-testing --name rescue --no-start
```

No DVD is attached and the VM boots from disk.

### Scripting many VMs

```bash
for i in 1 2 3; do
  ./scripts/create-vm.sh --iso ubuntu-24.04.iso --preset minimal-testing \
    --name "node$i" --ssh-port $((2200 + i)) --headless
done
```

The SSH ports are checked against existing VMs, so the loop does not collide
even if some ports are already taken.

### CI: validate without a hypervisor

```bash
./scripts/create-vm.sh --iso none --preset minimal-testing --dry-run
./scripts/validate-presets.sh
./tests/run-tests.sh
```

`--dry-run` and `--print-config` work without VirtualBox installed. The test
suite uses a fake `VBoxManage`, so no hypervisor is required either.

### Recreating a VM from scratch

```bash
./scripts/create-vm.sh --iso ubuntu-24.04.iso --preset dev --name dev --replace
```

`--replace` refuses to run non-interactively unless you also pass `--yes`, and
interactively it asks you to type the VM name. It deletes the VM **and its
disks**.

## Managing existing VMs

Two commands work on the VMs that are already registered, so you never have to
drop down to raw `VBoxManage` to see or remove one:

```bash
./scripts/create-vm.sh --list-vms
# NAME                         STATE       UUID
# ubuntu-24.04                 running     4f1c…-…
# debian-12                    powered off  9a02…-…

./scripts/create-vm.sh --delete-vm debian-12
```

`--delete-vm` refuses to touch a VM that is running (shut it down first), asks
you to type the VM name, and removes the registration **and the disks** — the
same destructive scope as `--replace`. Non-interactively it needs `--yes`:

```bash
./scripts/create-vm.sh --delete-vm debian-12 --yes
./scripts/create-vm.sh --delete-vm debian-12 --dry-run   # show, do not delete
```

Neither command needs `--iso` or `--preset`. `make vms` lists from the Makefile.

## Downloading the installer

`--download` accepts a catalog name or a URL and leaves the image in the cache,
so it is downloaded once and reused:

```bash
./scripts/create-vm.sh --list-isos
./scripts/create-vm.sh --download ubuntu-24.04-server --preset server
./scripts/create-vm.sh --download https://example.org/image.iso --name custom
```

Resolution, caching and checksum behaviour are documented in
[`ISOS.md`](ISOS.md).

## Unattended installs

`--unattended` makes VirtualBox answer the installer. VirtualBox generates the
answer file itself — `autounattend.xml` for Windows, preseed or kickstart for
Linux distros it supports — and attaches it to the VM, so you do not choose a
language, a keyboard, a time zone or a user by hand.

```bash
./scripts/create-vm.sh --download ubuntu-24.04-server --preset server \
  --unattended --user dev --hostname lab --locale en_US --timezone UTC
```

What EasyVbox does on top of `VBoxManage unattended install`:

- Passes the installer ISO, user, hostname, locale, country and time zone.
- Installs Guest Additions when the ISO is present (`--no-install-additions` to
  skip; the flag is dropped with a warning when the ISO is missing).
- Generates a password if you do not supply one and prints it **once** at the
  end. It is redacted as `***` in logs and in `--dry-run` output.
- Skips its own ISO attach and boot-order flags, because VirtualBox handles both
  in unattended mode (shown in the post-creation verification as "installer
  media (attached by VBoxManage unattended install)").

Password handling, in order of preference:

```bash
EASYVBOX_PASSWORD='...' ./scripts/create-vm.sh ... --unattended   # not in shell history
./scripts/create-vm.sh ... --unattended --password '...'          # visible in ps/history
./scripts/create-vm.sh ... --unattended                           # generated, shown once
```

### Provisioning the guest

Both options run through VirtualBox's post-install hook, which is why they
require `--unattended`:

```bash
# Your own script, inlined and executed after the installation finishes
./scripts/create-vm.sh --download ubuntu-24.04-server --preset server \
  --unattended --provision ~/bootstrap.sh --provision ~/tools.sh

# The common case
./scripts/create-vm.sh --download ubuntu-24.04-server --preset server \
  --unattended --with-docker
```

Details worth knowing:

- `--provision` base64-encodes the script and writes it to
  `/var/tmp/easyvbox-provision-<n>.sh` inside the guest, so no network access is
  needed to get it there.
- Scripts run as root after install; add `sudo -u "$SUDO_USER"` if something must
  belong to the interactive user.
- Provisioning needs Guest Additions: without them the hook may not run. EasyVbox
  warns when it cannot find them.
- Windows guests support `--unattended`, but not `--provision`/`--with-docker`:
  those are shell scripts (EasyVbox refuses with a clear message).

## Post-creation verification

After the VM is created (and before it starts), EasyVbox reads its
configuration back with `VBoxManage showvminfo --machinereadable` and compares
it with what was requested:

| Checked | Notes |
|---|---|
| Memory, CPUs, VRAM | Exact values |
| Firmware, graphics controller, TPM, Secure Boot | Case-insensitive |
| 3D acceleration, nested virtualization | `on` / `off` |
| USB controller | Matches the requested mode |
| Storage controllers | NVMe present when requested, SATA always |
| Disk and ISO | Attached to the expected controller and port |
| Boot order | `dvd` when there is an ISO, `disk` otherwise |
| Port forwards | SSH port and extra forwards |
| Shared folders | Registered with the expected name |

Each line is `✓` applied, `⚠` accepted but not applied, or `·` not reported by
this VirtualBox version. The difference matters: an option that a build does
not report is not a failure, while a reported value that differs is exactly the
silent-ignore case this check exists to catch.

Verification is **advisory**: a mismatch prints a warning with the log path and
the VM stays created (it is still usable, and you can fix the setting in the
GUI). Disable it with `--no-verify`.

```bash
$ ./scripts/create-vm.sh --iso ubuntu.iso --preset dev --no-verify
```

## Logs

Each real run writes a log with every command and its output:

```text
~/.easyvbox/logs/create-vm-20260101-120000-12345.log
```

The path is printed at the end of a run, and included in error messages. Use
`--log-file` to choose your own location, `--no-log` to disable, or
`EASYVBOX_LOG_DIR` to change the directory. Dry runs do not create a log unless
you pass `--log-file`.
