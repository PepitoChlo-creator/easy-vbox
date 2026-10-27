# Changelog

All notable changes to EasyVbox are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [3.0.0] — 2026-10-27

A full pass over correctness, presets, tests and documentation.

### Added

- **Test suite** (`tests/run-tests.sh`, 44 tests) that drives `create-vm.sh`
  against a fake `VBoxManage`, so the whole creation flow is verified in CI
  without a hypervisor.
- **Preset validator** (`scripts/validate-presets.sh`): JSON schema checks,
  value ranges, enum validation, documentation coverage.
- `--dry-run` now prints a readable, copy-pasteable plan and creates no files,
  folders or logs.
- `--print-config` to inspect the resolved configuration as `key=value`.
- `--no-nvme`, `--no-3d`, `--no-nested`, `--gui`, `--no-start`, `--replace`,
  `--machine-folder`, `--usb`, `--tpm`, `--secure-boot`, `--graphics`,
  `--firmware`, `--vram`, `--ostype`, `--forward`, `--hostonly-adapter`,
  `--intnet-name`.
- `--network` now supports `hostonly` and `intnet` in addition to `nat` and
  `bridged`.
- Size suffixes: `--ram 8G`, `--disk 60G`.
- Host-aware clamping of RAM/CPUs, with `--force-resources` to override.
- Automatic SSH port selection when `2222` is already taken by another VM.
- Bridged adapter auto-detection (default route interface).
- Shared folders accept a name and read-only mode: `--shared-folder code=~/src:ro`.
- Guest Additions helper can attach the ISO to a stopped VM
  (`--attach VM --guest ubuntu`).
- Logs in `~/.easyvbox/logs/` with `--log-file`, `--no-log` and
  `EASYVBOX_LOG_DIR`.
- `docs/TROUBLESHOOTING.md`, `docs/ADVANCED.md`, `CHANGELOG.md`, `Makefile`,
  CI matrix (Linux + macOS), full MIT license text.

### Fixed

- **NVMe storage was invalid**: NVMe must be created as `--add pcie
  --controller NVMe --portcount 1`, not `--add nvme --portcount 4`.
- **The installer ISO was attached to NVMe**, which cannot hold optical media.
  A separate SATA controller is now created for the DVD drive.
- **Windows 11 TPM flag was wrong** (`--tpm 2.0` instead of `--tpm-type 2.0`),
  so the `windows11` preset could not work. Secure Boot now falls back to
  `modifynvram secureboot --enable` on builds that reject `--secure-boot`.
- **Command-line flags were overwritten by presets**: `--ram 8G --preset game`
  silently used the preset value. Flags now always win.
- **`--list-presets` and `--help` required VirtualBox** and crashed without it.
- **Every preset was identical** (same RAM, CPU, disk). All 12 now have
  values that match their name.
- **`--shared-folder` could not be read-only or renamed** and did not expand `~`.
- **USB 3.0 was enabled unconditionally**, which breaks VM startup when the
  Extension Pack is missing. It is now detected and downgraded with a warning.
- **The VM folder was hardcoded** to `~/VirtualBox VMs`; the default machine
  folder is now read from VirtualBox, and `--machine-folder` exists.
- **Partial failures left orphan VMs** with no explanation. Errors now include
  the log path and the exact cleanup command.
- **`--dry-run` still created folders** (machine folder, shared folders) and a
  log file.
- `--headless` from a preset was ignored by the fallback preset parser.
- `install.sh` broke when run from another directory and blocked CI on `read`.
- Relative ISO paths are now resolved to absolute paths, as VirtualBox requires.
- Starting the VM no longer swallows errors.

### Changed

- Preset schema is now versioned (`"schema": 2`) and validated in CI.
- Presets gained `vram_mb`, `graphics_controller`, `firmware`, `tpm`,
  `secure_boot`, `nested_virt`, `usb`, `headless`, `shared_folder`,
  `port_forwards` and `tags`.
- `scripts/create-vm.sh` is still a single, dependency-free bash file, and now
  also works with macOS's bash 3.2.
- Documentation rewritten: install, presets, advanced usage, troubleshooting.

### Removed

- The `jq` requirement at runtime. Presets are parsed with pure bash; `jq` or
  `python3` is only used by the validator.

## [2.2.0] — prior release

- Initial public version: one command VM creation, 12 presets, Windows 11
  preset, dry run, shared folders.
