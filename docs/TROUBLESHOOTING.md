# Troubleshooting

Start with the log — every run prints its path and it contains the exact
`VBoxManage` command and VirtualBox's own error message.

```bash
tail -40 ~/.easyvbox/logs/create-vm-*.log
```

## VirtualBox is not found

```
✗ VirtualBox is not installed or VBoxManage is not in PATH
```

Install VirtualBox (`docs/INSTALL.md`), or point EasyVbox at the binary:

```bash
VBOXMANAGE=/usr/lib/virtualbox/VBoxManage ./scripts/create-vm.sh --iso image.iso
```

`--dry-run` and `--print-config` deliberately work without VirtualBox.

## "Kernel driver not installed (rc=-1908)" / "VT-x is not available"

```
VBoxManage: error: VT-x is not available (VERR_VMX_NO_VMX)
```

The CPU virtualization extensions are not available to VirtualBox:

```bash
# Linux: check the module
lsmod | grep vboxdrv
sudo modprobe vboxdrv

# Are the extensions used by something else?
ls /dev/kvm 2>/dev/null && echo "KVM present: VirtualBox and KVM can conflict"
```

- Enable VT-x / AMD-V (SVM) in the BIOS/UEFI.
- On Windows, Hyper-V, WSL2 and Windows Sandbox reserve the extensions. Disable
  Hyper-V or use the Hyper-V backend.
- On Linux, stop other hypervisors using KVM while VirtualBox runs.

## Windows 11 refuses to install

The `windows11` preset already raises RAM, CPU, disk, EFI, TPM 2.0 and Secure
Boot. If Setup still complains:

1. Check the version requirement — TPM 2.0 and Secure Boot need **VirtualBox
   7.0+**:
   ```bash
   VBoxManage --version
   ```
2. Verify the TPM was applied:
   ```bash
   VBoxManage showvminfo Win11 | grep -i tpm
   ```
3. Windows 11 also validates the CPU model. EasyVbox cannot change what
   VirtualBox reports; if that check blocks you, it is a Microsoft requirement,
   not an EasyVbox bug.

## Secure Boot could not be enabled

Some builds reject `--secure-boot`. EasyVbox detects that, warns, and enrols the
NVRAM keys instead:

```bash
VBoxManage modifynvram "VM" secureboot --enable
```

If neither works, update VirtualBox: Secure Boot was stabilised in the 7.x
series.

## USB 3.0 devices are not visible

USB 2.0/3.0 requires the **Extension Pack** matching your VirtualBox version.
EasyVbox checks for it and falls back to USB 1.1 with a warning. Install it and
re-run the command (or just enable USB later in the VM settings):

```bash
VBoxManage list extpacks
```

## The VM boots to the EFI shell instead of the installer

- Confirm the ISO is attached: `VBoxManage showvminfo VM | grep -i dvd`
- Older/UEFI-unaware images may need legacy BIOS:
  `--firmware bios`
- Some ISOs need you to press a key; click into the VM window and press Enter.

## The ISO was not attached (NVMe setups)

EasyVbox puts the disk on NVMe and the DVD on a separate SATA controller,
because NVMe cannot hold optical media. If you see only one controller, check
the log for the `storagectl`/`storageattach` lines.

## "VM 'x' already exists"

A VM with that name is registered (maybe from an earlier attempt). Either use
another name:

```bash
./scripts/create-vm.sh --iso image.iso --name image2
```

or recreate it deliberately:

```bash
./scripts/create-vm.sh --iso image.iso --name x --replace
```

`--replace` deletes the VM **and its disks**, asks interactively, and refuses to
run unattended unless you add `--yes`.

## SSH port already in use

EasyVbox scans the forwarding rules of all registered VMs and picks the next
free host port automatically, telling you which one it chose. To control it:

```bash
--ssh-port 2200     # explicit
--ssh-port none     # no forwarding
```

If the port is used by a non-VirtualBox process, EasyVbox cannot see it; pick
another port.

## Bridged networking does not get an IP

- The bridge adapter must be a real host interface:
  ```bash
  VBoxManage list bridgedifs | grep '^Name:'
  ```
- Wi-Fi adapters work for some chipsets but not all; try Ethernet.
- On Linux, make sure `vboxnetflt` is loaded.

## Shared folders are empty

Shared folders need Guest Additions inside the guest:

```bash
./scripts/install-guest-additions.sh --attach myvm --guest ubuntu
```

Then add your user to the `vboxsf` group and log out/in:

```bash
sudo usermod -aG vboxsf "$USER"
```

## Disk full / VM creation fails midway

EasyVbox checks free space before creating the disk and warns when it is tight.
If a run fails after `createvm`, it prints the exact cleanup command:

```bash
VBoxManage unregistervm "NAME" --delete
```

## 3D acceleration makes the guest unusable

VirtualBox 7.1.x has known 3D regressions. EasyVbox warns when it detects that
version with 3D enabled. Workaround:

```bash
./scripts/create-vm.sh --iso image.iso --preset dev --no-3d
```

or upgrade/downgrade VirtualBox.

## "Cannot create machine folder"

The default machine folder may not be writable. Check it and override it:

```bash
VBoxManage list systemproperties | grep -i "machine folder"
./scripts/create-vm.sh --iso image.iso --machine-folder ~/VMs
```

## A download fails or the checksum does not match

```text
✗ Could not read https://.../SHA256SUMS (no network, or the catalog entry is out of date)
✗ No file matching '*amd64-netinst.iso' in https://.../SHA256SUMS
✗ Checksum mismatch for image.iso (expected ..., got ...)
```

- A 404 or a pattern that no longer matches means upstream moved the file: edit
  the one line in `isos/catalog.tsv` (or pass `--download https://...` directly).
  Validate your change with `./scripts/validate-catalog.sh`.
- A checksum mismatch removes the downloaded file automatically. Re-run; if it
  keeps failing, your mirror or proxy is serving something else.
- Behind a proxy, set `https_proxy` for curl/wget; EasyVbox does not touch it.
- `--dry-run` never fails because the network is down: it resolves what it can
  and warns.

## Unattended install does not start

- Requires VirtualBox 6.1+ and a real installer ISO (`--iso none` is rejected).
- The answer file is generated by VirtualBox, so support depends on the distro:
  Debian/Ubuntu, RHEL-family, SUSE and Windows work; smaller distros may not.
  Check the log for `unattended install` lines.
- If the VM boots to the installer menu instead, the answer file was not picked
  up. Try without `--install-additions` first, and check that the ISO matches the
  distro (a netinst ISO needs network in the guest).
- Guest Additions ISO not found → EasyVbox warns and continues without it; the
  additions are then installed by hand, and `--provision` may not run.

## Provisioning did not run

- It needs `--unattended` (EasyVbox refuses earlier otherwise) and Guest
  Additions inside the guest, because the hook is executed by them.
- The generated command is visible in the VBoxManage log (`post-install-command`).
  Copy it into the guest to reproduce.
- Scripts run as root; `docker` group membership applies after the user logs in
  again, which is why the final report tells you the user.

## Still stuck?

Collect this and open an issue:

```bash
VBoxManage --version
uname -a
./scripts/create-vm.sh --iso image.iso --preset dev --print-config
tail -40 ~/.easyvbox/logs/create-vm-*.log
```
