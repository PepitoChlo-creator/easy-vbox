# Changelog

All notable changes to EasyVbox are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [3.1.0] — 2026-10-27

Three features that remove the remaining manual steps around a VM.

### Added

- **ISO downloads**: `--download NAME` (or a URL) resolves the current upstream
  file, verifies its SHA-256 and caches it in `~/.easyvbox/isos`, reusing it on
  later runs. `--list-isos` shows the catalog, `--iso-cache DIR` moves the
  cache. Entries are data (`isos/catalog.tsv`) and are validated in CI by
  `scripts/validate-catalog.sh`. Verified checksums come from upstream
  `SHA256SUMS` files, so point releases keep working without edits.
- **Unattended installs**: `--unattended` exposes VirtualBox's own answer-file
  generation (`autounattend.xml`, preseed, kickstart) with `--user`,
  `--password`, `--hostname`, `--locale`, `--country`, `--timezone` and
  `--install-additions`. A password is generated when omitted, printed once and
  redacted as `***` in logs and dry-run output.
- **Provisioning**: `--provision FILE` (repeatable) inlines shell scripts into
  the guest's post-install hook, and `--with-docker` installs Docker and adds the
  guest user to its group. Both require `--unattended` and are refused for
  Windows guests with an explanation.
- 19 new tests (69 total), including a fake downloader so download, cache reuse,
  checksum mismatch and direct URLs are covered without network access.
- `docs/ISOS.md`, plus `make catalog` and `make isos`.

### Changed

- `--dry-run` no longer needs the network for a planned download, and never
  leaks the guest password.
- README, ADVANCED and TROUBLESHOOTING document the new flow.

## [3.0.1] — 2026-10-27

- All user-facing messages are in English. The post-creation verification
  (added in 3.0.0) printed its labels in Spanish; the rest of the project was
  already English.
- The release workflow takes the release body from this changelog, so release
  notes stay in sync with the code.

## [3.0.0] — 2026-10-27

A full pass over correctness, presets, tests and documentation.

### Verified

- **Post-creation verification**: the VM configuration is read back from
  `showvminfo --machinereadable` and compared with what was requested (memory,
  CPU, VRAM, firmware, graphics, 3D, nested virtualization, TPM, Secure Boot,
  USB, controllers, disk, ISO, boot order, forwards, shared folders). Settings
  a VirtualBox build silently ignores are reported instead of going unnoticed.
  Advisory by design; `--no-verify` disables it.
- Real CI badge in the README instead of a static "tests passing" badge.
- `release` workflow: pushing a `v*` tag checks that the tag matches `VERSION`,
  runs the test suite, builds `easy-vbox-<version>.tar.gz` with a SHA-256
  checksum and publishes the GitHub release. The README documents installing
  from a release tarball, without git.

### Added

- **Test suite** (`tests/run-tests.sh`, 50 tests) that drives `create-vm.sh`
  against a fake `VBoxManage`, so the whole creation flow is verified in CI
  without a hypervisor. The mock stores the settings it receives and renders
  them through `showvminfo`, so tests assert the resulting configuration too.
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
