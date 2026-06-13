# EasyVbox 🚀

**Create great VirtualBox VMs in seconds, not 15 minutes of clicking.**

Tired of the VirtualBox wizard? Forgetting TPM for Windows 11? Using slow SATA disks by default? Never remembering "good settings"?

**EasyVbox solves this with one command and battle-tested presets.**

```bash
./scripts/create-vm.sh --iso ~/Downloads/ubuntu-24.04.iso --preset fullstack
```

## Why This Exists

Creating VMs in VirtualBox is unnecessarily painful for power users and developers.

EasyVbox gives you:
- Smart defaults based on your machine
- 12 high-quality presets for real use cases
- Automatic Windows 11 compliance (TPM 2.0 + Secure Boot)
- NVMe instead of slow SATA
- Easy bridged networking and shared folders
- Dry-run mode so you can see what will happen

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/easy-vbox.git
cd easy-vbox
chmod +x scripts/*.sh
./scripts/install.sh

./scripts/create-vm.sh --iso your.iso --preset dev
```

Or interactive:
```bash
./scripts/create-vm.sh
```

## Presets (12 total)

- `basic` — Quick tests
- `dev` — Daily development (recommended default)
- `fullstack` — Web + Docker + databases
- `server` — Homelab (headless)
- `desktop` — Comfortable daily use
- `gaming` — High performance
- `windows11` — Windows 11 (TPM + Secure Boot forced)
- `kali` — Penetration testing
- `ctf` — Capture The Flag
- `android-dev` — Android development (high RAM for emulators)
- `data-science` — ML / Jupyter
- `minimal-testing` — CI and lightweight testing

## Features

- Smart resource detection
- Bridged networking (`--network bridged`)
- Guest Additions helper
- One-command shared folders
- `--dry-run`
- Fully scriptable
- Works without extra tools (graceful fallbacks)

## Technical Highlights

- Always EFI
- Dynamic VDI disks
- NAT with SSH port 2222 by default
- Windows 11 preset forces minimum requirements + TPM 2.0 + Secure Boot
- Single-file main script for easy standalone use

## Contributing

Best contributions are new high-quality presets.

See `docs/PRESETS.md` and `CONTRIBUTING.md`.

## License

MIT

**Stop fighting the wizard. Start shipping.**
