# EasyVbox 🚀

**Create great VirtualBox VMs in seconds, not 15 minutes of clicking.**

[![test](https://github.com/PepitoChlo-creator/easy-vbox/actions/workflows/test.yml/badge.svg)](https://github.com/PepitoChlo-creator/easy-vbox/actions/workflows/test.yml)
[![release](https://img.shields.io/github/v/release/PepitoChlo-creator/easy-vbox?sort=semver)](https://github.com/PepitoChlo-creator/easy-vbox/releases)
![shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen)
![license](https://img.shields.io/badge/license-MIT-blue)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25)

```bash
./scripts/create-vm.sh --download ubuntu-24.04-desktop --preset dev --unattended
```

Tired of the VirtualBox wizard? Forgetting TPM for Windows 11? Getting a SATA
disk when you wanted NVMe? Never remembering "good settings"?

EasyVbox is one bash script and a set of battle-tested presets that create a
correct VM — storage, firmware, networking, clipboard — in one command.

---

## Why this exists

The VirtualBox GUI is fine for one VM and painful for the tenth. The CLI is
worse: `createvm`, `modifyvm`, `storagectl`, `storageattach`, `createmedium`
and a dozen flags in the right order, before you even install the guest.

EasyVbox wraps all of it with:

- **12 presets that are actually different** (RAM, CPUs, disk, 3D, USB, ports),
  not the same config with a different filename
- **Correct storage layout** — NVMe on the PCIe bus with a separate SATA
  controller for the installer DVD (NVMe cannot hold optical media)
- **Windows 11 compliance** — UEFI, TPM 2.0, Secure Boot and minimum resources
- **Graceful degradation** — detects VirtualBox version and Extension Pack,
  skips what your build cannot do instead of failing halfway
- **A dry-run plan you can read and paste**
- **Post-creation verification** — reads the VM back from VirtualBox and tells
  you if any setting was silently ignored
- **ISO downloads** — right image, verified, cached, no browser
- **Unattended installs** — no clicks inside the guest either

---

## Quick start

```bash
git clone https://github.com/PepitoChlo-creator/easy-vbox.git
cd easy-vbox

./scripts/install.sh                     # checks VirtualBox, makes scripts executable
./scripts/create-vm.sh --list-presets    # see the presets
./scripts/create-vm.sh --iso ubuntu.iso --preset dev --dry-run   # inspect the plan
./scripts/create-vm.sh --iso ubuntu.iso --preset dev             # build it
```

No git? Download the release tarball and use it directly:

```bash
curl -L -O https://github.com/PepitoChlo-creator/easy-vbox/releases/latest/download/easy-vbox-3.2.0.tar.gz
tar xzf easy-vbox-3.2.0.tar.gz && cd easy-vbox-3.2.0
./scripts/create-vm.sh --list-presets
```

Every release includes a `.sha256` checksum.

Interactive mode (no arguments) asks for the ISO and the preset:

```bash
./scripts/create-vm.sh
```

---

## The 60-second tour

`--dry-run` prints exactly what will run — nothing is created or modified:

```text
$ ./scripts/create-vm.sh --iso ubuntu-24.04.iso --preset fullstack --dry-run
# EasyVbox v3.2.0 — dry run plan (nothing will be changed)
# preset: fullstack
# vm: ubuntu-24.04 | iso: /home/you/ubuntu-24.04.iso | ram: 12288 MiB | cpus: 6
VBoxManage createvm --name ubuntu-24.04 --ostype Ubuntu_64 --register --basefolder '/home/you/VirtualBox VMs'
VBoxManage modifyvm ubuntu-24.04 --memory 12288 --cpus 6 --vram 64 --graphicscontroller vmsvga --firmware efi \
  --ioapic on --nestedpaging on --clipboard-mode bidirectional --draganddrop bidirectional --nested-hw-virt on \
  --usb on --nic1 nat --natpf1 ssh,tcp,,2222,,22 --natpf2 http,tcp,,8080,,80 --natpf3 https,tcp,,8443,,443
VBoxManage storagectl ubuntu-24.04 --name NVMe --add pcie --controller NVMe --portcount 1 --bootable on
VBoxManage storagectl ubuntu-24.04 --name SATA --add sata --controller IntelAhci --portcount 3 --bootable on
VBoxManage createmedium disk --filename '/home/you/VirtualBox VMs/ubuntu-24.04/ubuntu-24.04.vdi' \
  --size 102400 --variant Standard --format VDI
VBoxManage storageattach ubuntu-24.04 --storagectl NVMe --port 0 --device 0 --type hdd \
  --medium '/home/you/VirtualBox VMs/ubuntu-24.04/ubuntu-24.04.vdi' --nonrotational on
VBoxManage storageattach ubuntu-24.04 --storagectl SATA --port 1 --device 0 --type dvddrive \
  --medium /home/you/ubuntu-24.04.iso
VBoxManage modifyvm ubuntu-24.04 --boot1 dvd --boot2 disk
VBoxManage startvm ubuntu-24.04 --type gui
```

That is the whole trick: the plan is the implementation, so what you read is
what you get.

---

## Presets

| Preset | RAM | CPUs | Disk | What makes it different |
|---|---:|---:|---:|---|
| `basic` | 2 GiB | 2 | 25 GiB | Lightweight, no 3D, USB 1.1 for maximum compatibility |
| `dev` | 8 GiB | 4 | 60 GiB | **Recommended default**: 3D, nested virtualization, USB 3.0 |
| `fullstack` | 12 GiB | 6 | 100 GiB | Docker/web work; publishes `8080` and `8443` |
| `server` | 4 GiB | 2 | 50 GiB | Headless homelab box, no GPU, SSH only |
| `desktop` | 6 GiB | 4 | 80 GiB | Comfortable day-to-day desktop VM |
| `gaming` | 16 GiB | 8 | 120 GiB | 256 MiB VRAM, VBoxSVGA, 3D acceleration |
| `windows11` | 8 GiB | 4 | 128 GiB | UEFI + TPM 2.0 + Secure Boot enforced |
| `kali` | 6 GiB | 4 | 80 GiB | Nested virtualization for VMs inside the guest |
| `ctf` | 4 GiB | 2 | 40 GiB | Fast boot, no 3D, small footprint |
| `android-dev` | 8 GiB | 4 | 100 GiB | High RAM for emulators, nested virt, `adb` on 5555 |
| `data-science` | 16 GiB | 8 | 150 GiB | Big RAM/disk, Jupyter on 8888 |
| `minimal-testing` | 1 GiB | 1 | 10 GiB | Tiny headless CI VM, SATA only |

Any preset value can be overridden from the command line — **your flags win**:

```bash
./scripts/create-vm.sh --iso kali.iso --preset gaming --ram 8G --cpus 4 --no-3d
```

Details, schema and how to add your own: [`docs/PRESETS.md`](docs/PRESETS.md).

---

## What it does for you

**Smart defaults.** RAM/CPU are derived from the host and clamped to a safe
value (host RAM minus 2 GiB), so a 16 GiB preset on an 8 GiB laptop becomes
6 GiB with a warning instead of a swap storm. `--force-resources` overrides.

**Correct storage.** The default is an NVMe controller (`--add pcie
--controller NVMe --portcount 1`), which is where VirtualBox actually exposes
NVMe. The installer ISO goes on a separate SATA controller because NVMe does
not support DVD drives. Pick `--no-nvme` for classic SATA.

**Windows 11 without drama.** The `windows11` preset sets EFI, TPM 2.0, Secure
Boot and raises RAM/CPU/disk to Microsoft's minimums. On builds where
`--secure-boot` is unavailable, EasyVbox falls back to enrolling the NVRAM
keys.

**It knows what your VirtualBox can do.** Version checks gate TPM and Secure
Boot (7.0+), the Extension Pack gates USB 2.0/3.0, and 3D on 7.1.x gets a
warning about the known regressions. Optional settings that fail become
warnings, not half-created VMs.

**Networking that works.** NAT with SSH forwarded on `2222` by default; if that
host port is taken by another VM it picks the next free one. Also `bridged`
(with adapter auto-detection), `hostonly`, `intnet` and `none`, plus repeatable
`--forward name:host:guest` rules.

**Shared folders in one flag.** `--shared-folder ~/src` or
`--shared-folder code=~/src:ro`.

**It checks its own work.** After creating a VM, EasyVbox reads the
configuration back with `showvminfo` and compares it with what you asked for:
memory, CPUs, firmware, TPM, Secure Boot, controllers, the attached disk and
ISO, port forwards and shared folders. If a VirtualBox version accepts an
option but does not apply it, you see it immediately instead of discovering it
at boot:

```text
▶ Verifying the VM configuration
   ✓ memory (MiB): 8192
   ⚠ CPUs: expected '4', got '1'
   ✓ NVMe controller present
   ✓ ISO attached: ubuntu-24.04.iso
   ✓ SSH forwarded on host port 2222
⚠ Verification with warnings: 1 setting(s) not applied, 13 correct
```

The check is advisory (a warning never undoes a created VM) and can be skipped
with `--no-verify`. Fields a given VirtualBox version does not report are shown
as `·` instead of being counted as failures.

**It fetches the installer for you.** `--download NAME` resolves the current
upstream file from a catalog of official locations, verifies its SHA-256 and
caches it in `~/.easyvbox/isos`, so the second VM is free:

```bash
./scripts/create-vm.sh --list-isos
./scripts/create-vm.sh --download debian-12-netinst --preset server
./scripts/create-vm.sh --download https://example.org/custom.iso
```

**Zero clicks inside the guest too.** `--unattended` hands the installer to
VirtualBox's own answer-file machinery — `autounattend.xml` for Windows,
preseed/kickstart for Linux — so language, keyboard, timezone and user are
answered for you:

```bash
./scripts/create-vm.sh --download ubuntu-24.04-server --preset server \
  --unattended --user dev --hostname lab --with-docker
```

A password is generated and shown **once** at the end if you do not pass one,
and it never reaches the log (it is redacted as `***`).

**And it can finish the job.** `--provision setup.sh` inlines your script into
the guest's post-install hook, and `--with-docker` is the one-liner version:

```bash
./scripts/create-vm.sh --download kali-latest --preset kali \
  --unattended --provision ~/dotfiles/bootstrap.sh
```

**Safe by construction.** `--dry-run` changes nothing (not even a folder),
`--print-config` shows the resolved values, `--name` collisions are refused,
and `--replace` demands confirmation before deleting anything.

---

## Requirements

| Component | Notes |
|---|---|
| VirtualBox | 6.1+ (unattended installs); **7.0+** for TPM 2.0 and Secure Boot |
| Operating system | Linux and macOS. Windows via Git Bash works for the CLI, but nested virtualization is not available; run the VM from the Windows host |
| Shell | bash 3.2+ (macOS default bash works) |
| Dependencies | none for VM creation; `curl` or `wget` for `--download`; `jq` **or** `python3` only for `validate-presets.sh` |
| Extension Pack | optional; needed for USB 2.0/3.0 passthrough |

Apple Silicon macs can only run ARM guests and VirtualBox support there is
limited; x86 ISO images will not boot.

---

## Command-line cheat sheet

```bash
--iso PATH              Installer image ('none' for a blank VM)
--preset NAME           Start from a preset
--name NAME             VM name (default: derived from the ISO file name)
--ram 8G --cpus 4 --disk 60G --vram 128
--nvme / --no-nvme      Storage controller
--3d / --no-3d          Hardware 3D acceleration
--network nat|bridged|hostonly|intnet|none
--bridge-adapter eth0   Bridged interface (auto-detected by default)
--ssh-port 2222         Host port forwarded to guest 22 ('none' to disable)
--forward http:8080:80  Extra port forward (repeatable)
--shared-folder SPEC    [name=]PATH[:ro]
--headless | --no-start | --gui
--download NAME | --list-isos | --iso-cache DIR
--unattended --user NAME --password PASS --hostname NAME
--provision FILE | --with-docker
--list-vms              What VirtualBox has registered on this host
--delete-vm NAME --yes  Unregister a VM and delete its disks
--dry-run | --print-config | --list-presets | --list-isos | --no-verify
```

Full reference, examples and environment variables:
[`docs/ADVANCED.md`](docs/ADVANCED.md).

---

## Tests

No VirtualBox needed — the suite drives a fake `VBoxManage` and checks the exact
command sequence:

```bash
./tests/run-tests.sh          # the full suite
./tests/run-tests.sh -v       # show every VBoxManage call
./scripts/validate-presets.sh # schema + docs coverage of all presets
make test                     # both of the above + shellcheck, if installed
```

---

## Documentation

- [`docs/INSTALL.md`](docs/INSTALL.md) — installing VirtualBox and the Extension Pack
- [`docs/PRESETS.md`](docs/PRESETS.md) — every preset, the JSON schema, adding your own
- [`docs/ISOS.md`](docs/ISOS.md) — ISO catalog, downloads, cache and verification
- [`docs/ADVANCED.md`](docs/ADVANCED.md) — full flag reference and recipes
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — when VirtualBox says no
- [`CHANGELOG.md`](CHANGELOG.md) — what changed in each version

---

## Contributing

The most valuable contribution is a **real** preset with real values, validated
and documented. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).

**Stop fighting the wizard. Start shipping.**
