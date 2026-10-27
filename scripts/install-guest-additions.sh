#!/usr/bin/env bash
# Guest Additions helper.
#
# Two things make Guest Additions painful: finding the ISO and matching the
# kernel headers. This script attaches the ISO to a stopped VM and prints the
# exact commands to run inside the guest.
#
#   ./scripts/install-guest-additions.sh                     # interactive
#   ./scripts/install-guest-additions.sh --guest ubuntu
#   ./scripts/install-guest-additions.sh --attach dev --guest fedora
set -euo pipefail

GUEST=""
VM_NAME=""
ATTACH_ONLY=false

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi
ok()   { printf '%b✓%b %s\n' "$GREEN" "$NC" "$*"; }
info() { printf '%b▶%b %s\n' "$CYAN" "$NC" "$*"; }
warn() { printf '%b⚠%b %s\n' "$YELLOW" "$NC" "$*"; }
bad()  { printf '%b✗%b %s\n' "$RED" "$NC" "$*"; }

usage() {
  cat <<EOF
EasyVbox Guest Additions helper

Usage: $(basename "$0") [--guest NAME] [--attach VM] [--attach-only]

  -g, --guest NAME    Guest family: ubuntu, debian, kali, fedora, arch,
                      opensuse, alpine, windows
  -a, --attach VM     Attach the Guest Additions ISO to a stopped VM
      --attach-only   Only attach the ISO (skip the in-guest instructions)
  -h, --help          Show this help

Examples:
  $(basename "$0") --attach dev --guest ubuntu
  $(basename "$0") --guest fedora
EOF
}

while (( $# > 0 )); do
  case "$1" in
    -g|--guest)  GUEST="${2:-}"; shift 2 ;;
    -a|--attach) VM_NAME="${2:-}"; shift 2 ;;
    --attach-only) ATTACH_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) bad "Unknown option: $1"; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Locate VBoxManage and the Guest Additions ISO
# ---------------------------------------------------------------------------
VBOX=""
for candidate in \
  "$(command -v VBoxManage 2>/dev/null || true)" \
  /usr/lib/virtualbox/VBoxManage \
  /usr/local/bin/VBoxManage \
  /Applications/VirtualBox.app/Contents/MacOS/VBoxManage \
  "${VBOX_MSI_INSTALL_PATH:-}/VBoxManage.exe"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then VBOX="$candidate"; break; fi
done

GA_ISO=""
for candidate in \
  /usr/share/virtualbox/VBoxGuestAdditions.iso \
  /usr/lib/virtualbox/VBoxGuestAdditions.iso \
  /opt/VirtualBox/VBoxGuestAdditions.iso \
  /Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso \
  "${VBOX_MSI_INSTALL_PATH:-}/VBoxGuestAdditions.iso"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then GA_ISO="$candidate"; break; fi
done

# ---------------------------------------------------------------------------
# Attach the ISO to a VM (SATA port 2 is reserved for this)
# ---------------------------------------------------------------------------
attach_iso() {
  local vm="$1"
  [[ -n "$VBOX" ]] || { bad "VBoxManage not found; cannot attach the ISO"; return 1; }
  "$VBOX" list vms 2>/dev/null | grep -q "\"$vm\"" || { bad "VM '$vm' is not registered"; return 1; }
  if [[ -z "$GA_ISO" ]]; then
    bad "Guest Additions ISO not found on this host"
    printf '   Look for VBoxGuestAdditions.iso next to the VirtualBox binaries,\n'
    printf '   or use Devices → Insert Guest Additions CD image… in the VM window.\n'
    return 1
  fi
  local state
  state="$("$VBOX" showvminfo "$vm" --machinereadable 2>/dev/null | sed -n 's/^VMState="\(.*\)"$/\1/p' | head -n1)"
  if [[ "$state" != "poweroff" ]]; then
    bad "VM '$vm' is '$state'; shut it down before attaching the ISO"
    return 1
  fi
  if "$VBOX" storageattach "$vm" --storagectl "SATA" --port 2 --device 0 \
       --type dvddrive --medium "$GA_ISO" >/dev/null 2>&1; then
    ok "Attached $GA_ISO to '$vm' (SATA port 2)"
  else
    bad "Could not attach the ISO to '$vm'"
    printf '   Try manually:\n   %s storageattach "%s" --storagectl SATA --port 2 --device 0 --type dvddrive --medium "%s"\n' \
      "$VBOX" "$vm" "$GA_ISO"
    return 1
  fi
}

if [[ -n "$VM_NAME" ]]; then
  info "Attaching Guest Additions ISO to '$VM_NAME'"
  attach_iso "$VM_NAME" || exit 1
  $ATTACH_ONLY && exit 0
  printf '\n'
fi

# ---------------------------------------------------------------------------
# In-guest instructions
# ---------------------------------------------------------------------------
if [[ -z "$GUEST" ]]; then
  if [[ ! -t 0 ]]; then
    bad "No --guest given and no terminal to ask on"
    printf 'Pass one of: ubuntu, debian, kali, fedora, arch, opensuse, alpine, windows\n'
    exit 2
  fi
  read -rp "Guest family (ubuntu/debian/kali/fedora/arch/opensuse/alpine/windows): " GUEST
fi

GUEST="$(printf '%s' "$GUEST" | tr '[:upper:]' '[:lower:]')"

print_header() {
  printf '\n%bRun these commands INSIDE the VM:%b\n\n' "$CYAN" "$NC"
}

case "$GUEST" in
  ubuntu|debian|kali|mint|pop)
    print_header
    cat <<'EOF'
sudo apt update
sudo apt install -y build-essential dkms linux-headers-"$(uname -r)"
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
sudo /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot

If the CD is not at /dev/cdrom, find it with:  lsblk -o NAME,LABEL
EOF
    ;;
  fedora|rhel|rocky|alma|centos)
    print_header
    cat <<'EOF'
sudo dnf install -y kernel-devel-"$(uname -r)" kernel-headers gcc make perl
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
sudo /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot

If kernel-devel for the running kernel is unavailable, reboot into the newest
kernel first (the module must be built against the kernel you boot).
EOF
    ;;
  arch|manjaro|endeavour)
    print_header
    cat <<'EOF'
sudo pacman -S --needed base-devel linux-headers
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
sudo /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot

On Arch the official virtualbox-guest-utils package is usually a better choice
than the ISO when the host and guest versions match.
EOF
    ;;
  opensuse|suse)
    print_header
    cat <<'EOF'
sudo zypper install -y kernel-devel gcc make
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
sudo /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot
EOF
    ;;
  alpine)
    print_header
    cat <<'EOF'
sudo apk add gcc make musl-dev linux-lts-dev
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
sudo /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot
EOF
    ;;
  windows|win10|win11)
    print_header
    cat <<'EOF'
1. Open File Explorer and run the CD drive "VirtualBox Guest Additions".
2. Start VBoxWindowsAdditions.exe and accept the defaults.
3. Reboot the guest.
4. Then enable shared folders/clipboard in the VM settings if needed.
EOF
    ;;
  *)
    bad "Unknown guest family: $GUEST"
    printf 'Supported: ubuntu, debian, kali, fedora, arch, opensuse, alpine, windows\n'
    exit 2
    ;;
esac

printf '\n%bTips%b\n' "$CYAN" "$NC"
printf '  • Attach the ISO automatically next time: %s --attach <vm> --guest %s\n' "$(basename "$0")" "$GUEST"
printf '  • Shared folders need Guest Additions; add one with:\n'
printf '      ./scripts/create-vm.sh --iso IMAGE.iso --shared-folder ~/src\n'
printf '  • If the build fails, install the headers for the *running* kernel\n'
printf '    (uname -r) and re-run VBoxLinuxAdditions.run.\n'
