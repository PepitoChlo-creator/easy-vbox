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
| `--print-config` | Resolve preset + flags and print `key=value` lines |
| `-n, --dry-run` | Print the VBoxManage plan; modifies nothing |
| `-y, --yes` | Do not ask for confirmation (used by `--replace`) |
| `--log-file PATH` | Write the VBoxManage log to `PATH` |
| `--no-log` | Do not write a log file |

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
| `--usb MODE` | `off`, `ohci` (default), `ehci`, `xhci` |
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

## Environment variables

| Variable | Effect |
|---|---|
| `VBOXMANAGE` | Path to `VBoxManage` (otherwise searched in PATH and common locations) |
| `EASYVBOX_LOG_DIR` | Directory for logs (default `~/.easyvbox/logs`) |
| `EASYVBOX_PRESETS_DIR` | Alternative preset directory |
| `EASYVBOX_HOST_RAM_MB` | Override detected host RAM (handy for tests/CI) |
| `EASYVBOX_HOST_CPUS` | Override detected host CPU count |
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

## Logs

Each real run writes a log with every command and its output:

```text
~/.easyvbox/logs/create-vm-20260101-120000-12345.log
```

The path is printed at the end of a run, and included in error messages. Use
`--log-file` to choose your own location, `--no-log` to disable, or
`EASYVBOX_LOG_DIR` to change the directory. Dry runs do not create a log unless
you pass `--log-file`.
