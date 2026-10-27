# Installation

EasyVbox itself needs nothing but bash. The only real dependency is VirtualBox,
because it is the program doing the work.

## 1. Install VirtualBox

### Debian / Ubuntu / Mint

The distribution packages are fine for most people:

```bash
sudo apt update
sudo apt install -y virtualbox virtualbox-ext-pack
```

If you need the latest version (recommended for Windows 11 guests), use the
Oracle repository: <https://www.virtualbox.org/wiki/Linux_Downloads>

### Fedora

```bash
sudo dnf install -y VirtualBox VirtualBox-kmodsrc akmod-VirtualBox kernel-devel kernel-headers
sudo akmods --force
sudo systemctl restart vboxdrv
```

### Arch / Manjaro

```bash
sudo pacman -S --needed virtualbox virtualbox-host-modules-arch
sudo modprobe vboxdrv
```

### openSUSE

```bash
sudo zypper install -y virtualbox virtualbox-host-kmp-default
sudo modprobe vboxdrv
```

### macOS

```bash
brew install --cask virtualbox
```

Or download the `.dmg` from <https://www.virtualbox.org/wiki/Downloads> (Apple
Silicon hosts can only run ARM guests).

### Windows

Install the official installer. Then run EasyVbox from **Git Bash**, with
`VBoxManage.exe` either in `PATH` or with `VBOX_MSI_INSTALL_PATH` set. Note that
VirtualBox cannot run inside WSL2 with nested virtualization enabled by default;
run the command from the Windows host instead.

## 2. Load the kernel modules (Linux, once per boot)

```bash
sudo modprobe vboxdrv
# only needed if you use bridged/host-only networking:
sudo modprobe vboxnetadp vboxnetflt
```

Permanent setup (so it survives reboots):

```bash
echo -e "vboxdrv\nvboxnetadp\nvboxnetflt" | sudo tee /etc/modules-load.d/virtualbox.conf
```

Check that everything is loaded:

```bash
lsmod | grep vbox
```

If `VBoxManage` is not in `PATH`, EasyVbox also looks in `/usr/lib/virtualbox`,
`/usr/local/bin`, `/Applications/VirtualBox.app/Contents/MacOS` and
`$VBOX_MSI_INSTALL_PATH`. You can always point it explicitly:

```bash
VBOXMANAGE=/usr/lib/virtualbox/VBoxManage ./scripts/create-vm.sh --list-presets
```

## 3. Extension Pack (optional)

The Extension Pack adds USB 2.0/3.0 passthrough and VRDP. It must match the
VirtualBox version exactly.

```bash
VBoxManage list extpacks          # is it already installed?
VBoxManage extpack install --replace Oracle_VM_VirtualBox_Extension_Pack-7.1.6.vbox-extpack
```

Without it, EasyVbox silently falls back to USB 1.1 and tells you why. Nothing
else breaks.

## 4. Get EasyVbox

```bash
git clone https://github.com/PepitoChlo-creator/easy-vbox.git
cd easy-vbox
./scripts/install.sh
```

`install.sh` makes the scripts executable, reports the VirtualBox version,
detects a missing Extension Pack and offers to install the optional helpers
(`jq`, `zenity`). It never installs VirtualBox itself.

Non-interactive usage:

```bash
./scripts/install.sh --yes          # nothing optional
./scripts/install.sh --tools        # install helpers without asking
```

## 5. Verify

```bash
./scripts/create-vm.sh --version
./scripts/create-vm.sh --list-presets
./scripts/create-vm.sh --iso ~/Downloads/ubuntu-24.04.iso --preset dev --dry-run
./tests/run-tests.sh
```

If the dry run prints a plan, you are ready. Remove `--dry-run` to create the
VM.

## Guest Additions

Guest Additions give you clipboard sharing, dynamic resolution and shared
folders, and they must be installed **inside the guest**. The helper attaches
the ISO to a stopped VM and prints the right commands for your distribution:

```bash
./scripts/install-guest-additions.sh --attach dev --guest ubuntu
```

It uses SATA port 2, which EasyVbox leaves free for exactly this purpose.

## Uninstalling

There is nothing to uninstall: EasyVbox is a folder of scripts. Remove VMs with
VirtualBox itself (`VBoxManage unregistervm NAME --delete`) and delete the
clone.
