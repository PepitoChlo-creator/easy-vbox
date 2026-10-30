#!/usr/bin/env bash
# EasyVbox installer — checks your host and prepares the scripts.
#
#   ./scripts/install.sh              # interactive checks + optional helpers
#   ./scripts/install.sh --yes        # no questions, install nothing optional
#   ./scripts/install.sh --no-tools   # skip optional helper installation
#
# This script never installs VirtualBox itself: installing a hypervisor is a
# system decision that deserves your explicit attention.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The version lives in create-vm.sh only: two copies drift apart (this file was
# still claiming 3.0.0 when the project shipped 3.1.0).
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT_DIR/scripts/create-vm.sh" 2>/dev/null | head -n1)"
[[ -n "$VERSION" ]] || VERSION="unknown"
ASSUME_YES=false
INSTALL_TOOLS="ask"

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
EasyVbox installer v$VERSION

Usage: $(basename "$0") [options]

  -y, --yes       Assume yes; do not install optional helper tools
      --tools     Install optional helper tools without asking
      --no-tools  Do not install anything optional
  -h, --help      Show this help

The installer makes the scripts executable, checks that VirtualBox is present
and (optionally) offers to install jq/zenity for a nicer experience.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    -y|--yes)   ASSUME_YES=true; INSTALL_TOOLS="no"; shift ;;
    --tools)    INSTALL_TOOLS="yes"; shift ;;
    --no-tools) INSTALL_TOOLS="no"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) bad "Unknown option: $1"; usage; exit 2 ;;
  esac
done

printf 'EasyVbox installer v%s\n\n' "$VERSION"

# ---------------------------------------------------------------------------
# 1. Make the scripts runnable (absolute paths: works from any directory)
# ---------------------------------------------------------------------------
chmod +x "$ROOT_DIR"/scripts/*.sh 2>/dev/null || true
chmod +x "$ROOT_DIR"/tests/run-tests.sh "$ROOT_DIR/tests/mock/VBoxManage" 2>/dev/null || true
ok "Scripts are executable"

# ---------------------------------------------------------------------------
# 2. Operating system / package manager
# ---------------------------------------------------------------------------
PKG=""
SUDO=""
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) OS="macOS"; command -v brew >/dev/null 2>&1 && PKG="brew" ;;
  Linux)  OS="Linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="Windows (Git Bash)" ;;
  *) OS="unknown" ;;
esac
if [[ "$OS" == "Linux" ]]; then
  for candidate in apt-get dnf pacman zypper; do
    if command -v "$candidate" >/dev/null 2>&1; then PKG="$candidate"; break; fi
  done
fi
if [[ -n "$PKG" && "$PKG" != "brew" && "$(id -u)" != "0" ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi
info "Host: $OS${PKG:+ (package manager: $PKG)}"

# ---------------------------------------------------------------------------
# 3. VirtualBox
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

if [[ -n "$VBOX" ]]; then
  ok "VirtualBox found: $("$VBOX" --version | head -n1)"
  if "$VBOX" list extpacks 2>/dev/null | grep -qi "Oracle VM VirtualBox Extension Pack"; then
    ok "Extension Pack installed (USB 3.0 / VRDP support)"
  else
    warn "Extension Pack not found: USB 2.0/3.0 will be unavailable."
    printf '   Download the pack matching your version: https://www.virtualbox.org/wiki/Downloads\n'
  fi
else
  bad "VirtualBox (VBoxManage) was not found"
  case "$PKG" in
    apt-get) printf '   Debian/Ubuntu:  sudo apt install virtualbox virtualbox-ext-pack\n' ;;
    dnf)     printf '   Fedora:         sudo dnf install VirtualBox VirtualBox-kmodsrc akmod-VirtualBox\n' ;;
    pacman)  printf '   Arch:           sudo pacman -S virtualbox virtualbox-host-modules-arch\n' ;;
    zypper)  printf '   openSUSE:       sudo zypper install virtualbox virtualbox-host-kmp-default\n' ;;
    brew)    printf '   macOS:          brew install --cask virtualbox\n' ;;
    *)       printf '   Download:       https://www.virtualbox.org/wiki/Downloads\n' ;;
  esac
  printf '   Then reboot (or load the kernel modules) and run this installer again.\n'
  printf '   See docs/INSTALL.md for details.\n\n'
fi

# ---------------------------------------------------------------------------
# 4. Optional helper tools
# ---------------------------------------------------------------------------
MISSING=()
command -v jq >/dev/null 2>&1      || MISSING+=(jq)
command -v python3 >/dev/null 2>&1 || MISSING+=(python3)
[[ ${#MISSING[@]} -gt 0 ]] && warn "Optional tools missing: ${MISSING[*]} (used for preset validation)"

install_tools() {
  case "$PKG" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y jq zenity ;;
    dnf)     $SUDO dnf install -y jq zenity ;;
    pacman)  $SUDO pacman -S --needed --noconfirm jq zenity ;;
    zypper)  $SUDO zypper --non-interactive install jq zenity ;;
    brew)    brew install jq ;;
    *)       warn "No supported package manager found; install jq manually"; return 1 ;;
  esac
}

if [[ -n "$PKG" ]]; then
  do_install=false
  case "$INSTALL_TOOLS" in
    yes) do_install=true ;;
    no)  do_install=false ;;
    ask)
      if $ASSUME_YES || [[ ! -t 0 ]]; then
        do_install=false
      else
        printf '\n'
        read -rp "Install optional helpers (jq, zenity) with $PKG? [y/N] " answer
        [[ "$answer" =~ ^[Yy] ]] && do_install=true
      fi
      ;;
  esac
  if $do_install; then
    info "Installing optional helpers with $PKG"
    if install_tools; then ok "Helpers installed"; else warn "Helper installation failed (not required)"; fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. Next steps
# ---------------------------------------------------------------------------
printf '\n%bDone.%b Try:\n' "$GREEN" "$NC"
printf '  ./scripts/create-vm.sh --list-presets\n'
printf '  ./scripts/create-vm.sh --iso ~/Downloads/ubuntu-24.04.iso --preset dev --dry-run\n'
printf '  ./scripts/create-vm.sh --iso ~/Downloads/ubuntu-24.04.iso --preset dev\n'
printf '\nTests:  ./tests/run-tests.sh\nDocs:   README.md, docs/INSTALL.md, docs/PRESETS.md\n'
