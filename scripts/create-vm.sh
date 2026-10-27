#!/usr/bin/env bash
# EasyVbox — create great VirtualBox VMs in seconds.
#
#   ./scripts/create-vm.sh --iso IMAGE.iso [--preset NAME] [options]
#
# Exit codes: 0 = success, 1 = runtime failure, 2 = usage error.
#
# This script is intentionally a single file so it can be copied standalone.
set -euo pipefail

VERSION="3.0.0"
PROG="easy-vbox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESETS_DIR="${EASYVBOX_PRESETS_DIR:-$SCRIPT_DIR/../presets}"

# ---------------------------------------------------------------------------
# Output helpers (human messages -> stderr, machine output -> stdout)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

die()      { printf '%b✗ %s%b\n' "$RED" "$*" "$NC" >&2; exit 1; }
die_usage(){ printf '%b✗ %s%b\n' "$RED" "$*" "$NC" >&2; printf 'Run "%s --help" for usage.\n' "$PROG" >&2; exit 2; }
success()  { printf '%b✓ %s%b\n' "$GREEN" "$*" "$NC" >&2; }
info()     { printf '%b▶ %s%b\n' "$CYAN" "$*" "$NC" >&2; }
warn()     { printf '%b⚠ %s%b\n' "$YELLOW" "$*" "$NC" >&2; }

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE=""
LOG_FILE_EXPLICIT=false
log_init() {
  if $DRY_RUN && ! $LOG_FILE_EXPLICIT; then
    LOG_FILE="/dev/null"
    return 0
  fi
  [[ -n "$LOG_FILE" ]] || LOG_FILE="${EASYVBOX_LOG_DIR:-$HOME/.easyvbox/logs}/create-vm-$(date +%Y%m%d-%H%M%S)-$$.log"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  : >"$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
}
log() {
  [[ -n "$LOG_FILE" ]] || return 0
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

render_cmd() { local out="" a; for a in "$@"; do out+="$(printf '%q' "$a") "; done; printf '%s' "${out% }"; }

# Human-friendly quoting for the dry-run plan (still safe to copy/paste).
render_pretty() {
  local out="" a
  for a in "$@"; do
    if [[ -z "$a" ]]; then out+="'' "
    elif [[ "$a" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]]; then out+="$a "
    elif [[ "$a" != *"'"* ]]; then out+="'$a' "
    else out+="$(printf '%q' "$a") "
    fi
  done
  printf '%s' "${out% }"
}

LAST_VBOX_ERROR=""
vbox() {
  local rendered rc=0 bin="${VBOX_BIN:-VBoxManage}"
  rendered="$(render_cmd "$bin" "$@")"
  if $DRY_RUN; then
    render_pretty "$bin" "$@"; printf '\n'
    return 0
  fi
  log "RUN: $rendered"
  "$bin" "$@" >>"$LOG_FILE" 2>&1 || rc=$?
  if (( rc != 0 )); then
    LAST_VBOX_ERROR="$(tail -n 3 "$LOG_FILE" 2>/dev/null || true)"
    log "FAILED ($rc): $rendered"
  fi
  return $rc
}

# Like vbox(), but a failure is a warning instead of a hard stop.
vbox_soft() {
  local rc=0
  vbox "$@" || rc=$?
  if (( rc != 0 )); then
    warn "Optional setting failed: $(render_cmd "$@")"
    [[ -n "$LAST_VBOX_ERROR" ]] && printf '   %s\n' "$LAST_VBOX_ERROR" >&2
  fi
  return 0
}

dry_note() { if $DRY_RUN; then printf '# fallback if unsupported: %s\n' "$*"; fi; }

# ---------------------------------------------------------------------------
# Defaults / state
# ---------------------------------------------------------------------------
VBOX_BIN=""
VBOX_KNOWN=false
VBOX_VERSION="unknown"
VBOX_MAJOR=0
VBOX_MINOR=0
HOST_CPUS=0
HOST_RAM_MB=0
HOST_OS="unknown"
DEFAULT_MACHINE_FOLDER=""
HAS_EXTPACK=false
VBOX_OSTYPES=""

VM_NAME="" ISO_PATH="" PRESET=""
RAM_MB="" CPUS="" DISK_MB="" VRAM_MB=""
USE_NVME="" ENABLE_3D="" NESTED_VIRT="" TPM_TYPE="" SECURE_BOOT=""
USB_MODE="" GRAPHICS="" FIRMWARE=""
HEADLESS="" SHARED_FOLDER="" SHARED_NAME="HostShare" SHARED_RO=false
NETWORK_TYPE="" BRIDGE_ADAPTER="" HOSTONLY_ADAPTER="" INTNET_NAME=""
SSH_PORT="" EXTRA_FORWARDS=""
START_MODE="" DRY_RUN=false VERIFY=true FORCE_RESOURCES=false ASSUME_YES=false
REPLACE=false PRINT_CONFIG=false OSTYPE_OVERRIDE="" OSTYPE_WANTED="" ACTIVE_MACHINE_FOLDER=""

VM_REGISTERED_BY_US=false
CREATED_OK=false

# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------
detect_host() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) HOST_OS="macos" ;;
    Linux)  HOST_OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*) HOST_OS="windows" ;;
    *) HOST_OS="unknown" ;;
  esac

  if [[ -n "${EASYVBOX_HOST_CPUS:-}" ]]; then
    HOST_CPUS="$EASYVBOX_HOST_CPUS"
  elif command -v nproc >/dev/null 2>&1; then
    HOST_CPUS="$(nproc 2>/dev/null || echo 2)"
  elif command -v sysctl >/dev/null 2>&1; then
    HOST_CPUS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  else
    HOST_CPUS=2
  fi
  [[ "$HOST_CPUS" =~ ^[0-9]+$ ]] && (( HOST_CPUS > 0 )) || HOST_CPUS=2

  if [[ -n "${EASYVBOX_HOST_RAM_MB:-}" ]]; then
    HOST_RAM_MB="$EASYVBOX_HOST_RAM_MB"
  elif [[ "$HOST_OS" == "linux" && -r /proc/meminfo ]]; then
    HOST_RAM_MB="$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 4096)"
  elif [[ "$HOST_OS" == "macos" ]] && command -v sysctl >/dev/null 2>&1; then
    HOST_RAM_MB="$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1024/1024}' || echo 4096)"
  else
    HOST_RAM_MB=4096
  fi
  [[ "$HOST_RAM_MB" =~ ^[0-9]+$ ]] && (( HOST_RAM_MB > 0 )) || HOST_RAM_MB=4096
}

find_vboxmanage() {
  if [[ -n "${VBOXMANAGE:-}" ]]; then
    [[ -x "$VBOXMANAGE" ]] && { VBOX_BIN="$VBOXMANAGE"; return 0; }
    return 1
  fi
  if command -v VBoxManage >/dev/null 2>&1; then
    VBOX_BIN="$(command -v VBoxManage)"; return 0
  fi
  local candidate
  for candidate in \
    "/usr/lib/virtualbox/VBoxManage" \
    "/usr/local/bin/VBoxManage" \
    "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage" \
    "${VBOX_MSI_INSTALL_PATH:-}/VBoxManage.exe" \
    "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then VBOX_BIN="$candidate"; return 0; fi
  done
  return 1
}

vbox_version_info() {
  [[ -n "$VBOX_BIN" ]] || return 0
  VBOX_VERSION="$("$VBOX_BIN" --version 2>/dev/null | head -n1 | sed 's/^[^0-9]*//' || true)"
  [[ -n "$VBOX_VERSION" ]] || VBOX_VERSION="unknown"
  local major minor
  major="$(printf '%s' "$VBOX_VERSION" | cut -d. -f1)"
  minor="$(printf '%s' "$VBOX_VERSION" | cut -d. -f2)"
  [[ "$major" =~ ^[0-9]+$ ]] && VBOX_MAJOR="$major" || VBOX_MAJOR=0
  [[ "$minor" =~ ^[0-9]+$ ]] && VBOX_MINOR="$minor" || VBOX_MINOR=0
}

load_vbox_environment() {
  [[ -n "$VBOX_BIN" ]] || return 0

  local props
  props="$("$VBOX_BIN" list systemproperties --machinereadable 2>/dev/null || true)"
  DEFAULT_MACHINE_FOLDER="$(printf '%s\n' "$props" | sed -n 's/^defaultMachineFolder="\(.*\)"$/\1/p')"
  if [[ -z "$DEFAULT_MACHINE_FOLDER" ]]; then
    DEFAULT_MACHINE_FOLDER="$(printf '%s\n' "$props" | sed -n 's/^Default machine folder:[[:space:]]*//p')"
  fi
  [[ -n "$DEFAULT_MACHINE_FOLDER" ]] || DEFAULT_MACHINE_FOLDER="$HOME/VirtualBox VMs"

  local extpacks
  extpacks="$("$VBOX_BIN" list extpacks 2>/dev/null || true)"
  if printf '%s\n' "$extpacks" | grep -qi "Oracle VM VirtualBox Extension Pack"; then
    HAS_EXTPACK=true
  fi

  VBOX_OSTYPES="$("$VBOX_BIN" list ostypes 2>/dev/null | sed -n 's/^ID:[[:space:]]*//p' || true)"
}

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------
is_true()  { [[ "${1:-false}" == "true" ]]; }
is_false() { [[ "${1:-false}" == "false" ]]; }

have() { command -v "$1" >/dev/null 2>&1; }

# parse_size "8G" -> 8192 (MiB). Bare numbers are treated as MiB.
parse_size() {
  local raw="$1" num unit
  raw="${raw//[[:space:]]/}"
  if [[ ! "$raw" =~ ^([0-9]+)([GgMmKkTt]?[Bb]?)$ ]]; then
    return 1
  fi
  num="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]:-}"
  case "${unit:0:1}" in
    K|k) num=$(( num / 1024 )) ;;
    G|g) num=$(( num * 1024 )) ;;
    T|t) num=$(( num * 1024 * 1024 )) ;;
    *)   ;;
  esac
  printf '%s' "$num"
}

require_positive_int() {
  local name="$1" value="$2" min="$3" max="$4"
  [[ "$value" =~ ^[0-9]+$ ]] || die_usage "$name must be a number (got: '$value')"
  (( value >= min )) || die_usage "$name must be >= $min (got: $value)"
  (( value <= max )) || die_usage "$name must be <= $max (got: $value)"
}

# Flat-JSON reader: works without jq/python. Presets use a flat schema.
json_get() {
  local file="$1" key="$2" raw re
  [[ -r "$file" ]] || return 0
  raw="$(tr '\n' ' ' <"$file")"
  re="\"${key}\"[[:space:]]*:[[:space:]]*(\"([^\"]*)\"|(-?[0-9]+)|(true|false|null))"
  if [[ "$raw" =~ $re ]]; then
    if [[ "${BASH_REMATCH[2]:-}" != "" ]]; then
      printf '%s' "${BASH_REMATCH[2]}"
    elif [[ "${BASH_REMATCH[3]:-}" != "" ]]; then
      printf '%s' "${BASH_REMATCH[3]}"
    elif [[ "${BASH_REMATCH[4]:-}" != "" && "${BASH_REMATCH[4]}" != "null" ]]; then
      printf '%s' "${BASH_REMATCH[4]}"
    fi
  fi
  return 0
}

vm_exists() {
  local wanted="$1" name
  [[ -n "$VBOX_BIN" ]] || return 1
  while IFS= read -r name; do
    [[ "$name" == "$wanted" ]] && return 0
  done < <("$VBOX_BIN" list vms 2>/dev/null | sed -n 's/^"\(.*\)" {[^}]*}$/\1/p')
  return 1
}

list_vm_names() {
  [[ -n "$VBOX_BIN" ]] || return 0
  "$VBOX_BIN" list vms 2>/dev/null | sed -n 's/^"\(.*\)" {[^}]*}$/\1/p'
}

used_host_ports() {
  [[ -n "$VBOX_BIN" ]] || return 0
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    "$VBOX_BIN" showvminfo "$name" --machinereadable 2>/dev/null \
      | awk -F'"' '/^Forwarding\(/{split($2,f,","); if (f[4] ~ /^[0-9]+$/) print f[4]}'
  done < <(list_vm_names)
}

pick_ssh_port() {
  local port="$1" used
  used="$(used_host_ports | sort -u)"
  while printf '%s\n' "$used" | grep -qx "$port"; do
    port=$(( port + 1 ))
    (( port <= 65535 )) || die "No free host port found for SSH forwarding"
  done
  printf '%s' "$port"
}

# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------
list_presets() {
  local f name desc ram cpus disk tags
  printf '%-16s %-7s %-6s %-8s %-6s %s\n' "PRESET" "RAM" "CPUs" "DISK" "NVMe" "DESCRIPTION"
  for f in "$PRESETS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .json)"
    desc="$(json_get "$f" description)"
    ram="$(json_get "$f" ram_mb)"; cpus="$(json_get "$f" cpus)"; disk="$(json_get "$f" disk_mb)"
    tags="$(json_get "$f" nvme)"
    printf '%-16s %-7s %-6s %-8s %-6s %s\n' \
      "$name" "$(( ${ram:-0} / 1024 ))G" "${cpus:-?}" "$(( ${disk:-0} / 1024 ))G" "${tags:-false}" "$desc"
  done
}

load_preset() {
  local name="$1" f
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die_usage "Invalid preset name: '$name'"
  f="$PRESETS_DIR/$name.json"
  [[ -f "$f" ]] || die_usage "Preset not found: '$name' (use --list-presets to see all)"
  PRESET="$name"
  info "Preset: $name — $(json_get "$f" description)"

  # Command-line values always win: only fill the gaps.
  [[ -n "$RAM_MB" ]]       || RAM_MB="$(json_get "$f" ram_mb)"
  [[ -n "$CPUS" ]]         || CPUS="$(json_get "$f" cpus)"
  [[ -n "$DISK_MB" ]]      || DISK_MB="$(json_get "$f" disk_mb)"
  [[ -n "$VRAM_MB" ]]      || VRAM_MB="$(json_get "$f" vram_mb)"
  [[ -n "$USE_NVME" ]]     || USE_NVME="$(json_get "$f" nvme)"
  [[ -n "$ENABLE_3D" ]]    || ENABLE_3D="$(json_get "$f" accelerate_3d)"
  [[ -n "$NESTED_VIRT" ]]  || NESTED_VIRT="$(json_get "$f" nested_virt)"
  [[ -n "$GRAPHICS" ]]     || GRAPHICS="$(json_get "$f" graphics_controller)"
  [[ -n "$FIRMWARE" ]]     || FIRMWARE="$(json_get "$f" firmware)"
  [[ -n "$USB_MODE" ]]     || USB_MODE="$(json_get "$f" usb)"
  [[ -n "$HEADLESS" ]]     || HEADLESS="$(json_get "$f" headless)"
  [[ -n "$SHARED_FOLDER" ]] || SHARED_FOLDER="$(json_get "$f" shared_folder)"
  [[ -n "$EXTRA_FORWARDS" ]] || EXTRA_FORWARDS="$(json_get "$f" port_forwards)"

  local tpm sb
  tpm="$(json_get "$f" tpm)"; sb="$(json_get "$f" secure_boot)"
  [[ -n "$TPM_TYPE" ]] || TPM_TYPE="$tpm"
  [[ -n "$SECURE_BOOT" ]] || SECURE_BOOT="$sb"
  return 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
print_help() {
  cat <<EOF
EasyVbox v$VERSION — create VirtualBox VMs from ISO in seconds.

USAGE
  $PROG --iso IMAGE.iso [--preset NAME] [OPTIONS]
  $PROG --list-presets
  $PROG --iso ubuntu.iso --preset dev --dry-run

GENERAL
  -h, --help                Show this help and exit
  -V, --version             Show version and exit
      --list-presets        List available presets and exit
      --print-config        Show the resolved configuration and exit
  -n, --dry-run             Print the VBoxManage plan, change nothing
  -y, --yes                 Assume yes for confirmation prompts
      --log-file PATH       Write the VBoxManage log to PATH
      --no-verify           Skip the post-creation configuration check

VM
      --iso PATH            Installer image ('none' to skip the DVD drive)
      --name NAME           VM name (default: derived from the ISO filename)
      --preset NAME         Preset to start from (see --list-presets)
      --ostype TYPE         Override the detected VirtualBox OS type
      --ram SIZE            RAM in MiB, or with a unit: 8192, 8G
      --cpus N              Virtual CPUs
      --disk SIZE           Disk size in MiB, or with a unit: 61440, 60G
      --vram N              Video memory in MiB (max 256)
      --nvme / --no-nvme    Use an NVMe controller instead of SATA
      --3d / --no-3d        Enable or disable 3D acceleration
      --graphics TYPE       vmsvga | vboxsvga | none
      --firmware TYPE       efi | bios
      --nested / --no-nested  Expose hardware virtualization to the guest
      --usb MODE            off | ohci | ehci | xhci
      --tpm TYPE            none | 2.0
      --secure-boot on|off  Enable UEFI Secure Boot (needs TPM-capable VBox 7+)
      --machine-folder PATH Where the VM files are stored
      --force-resources     Do not clamp RAM/CPUs to host capacity

STARTUP
      --gui                 Start with a window (default)
      --headless            Start without a window
      --no-start            Create the VM but do not start it
      --replace             Delete and recreate an existing VM (asks first)

NETWORK
      --network TYPE        nat (default) | bridged | hostonly | intnet | none
      --bridge-adapter NAME Bridged interface (default: auto-detected)
      --hostonly-adapter N  Host-only interface (default: first available)
      --intnet-name NAME    Internal network name
      --ssh-port PORT       Host port forwarded to guest port 22 (default: 2222)
      --forward SPEC        Extra forward, NAME:HOSTPORT:GUESTPORT (repeatable)

SHARING
      --shared-folder SPEC  [name=]PATH[:ro] shared into the guest
      --shared-name NAME    Share name (default: HostShare)

EXAMPLES
  $PROG --iso ~/Downloads/ubuntu-24.04.iso --preset dev
  $PROG --iso ~/Downloads/Win11.iso --preset windows11 --name Win11
  $PROG --iso ~/Downloads/kali.iso --preset kali --ram 8G --cpus 4 --no-start
  $PROG --iso debian.iso --network bridged --bridge-adapter enp3s0 --shared-folder ~/src
  $PROG --iso debian.iso --preset server --headless --ssh-port 2200

Exit codes: 0 success, 1 runtime failure, 2 usage error.
EOF
}

opt_value() { printf '%s' "${1#*=}"; }

parse_args() {
  local arg key val
  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      -h|--help)       print_help; exit 0 ;;
      -V|--version)    printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
      --list-presets)  list_presets; exit 0 ;;
      --print-config)  PRINT_CONFIG=true; shift ;;
      -n|--dry-run)    DRY_RUN=true; shift ;;
      -y|--yes)        ASSUME_YES=true; shift ;;
      --force-resources) FORCE_RESOURCES=true; shift ;;
      --replace)       REPLACE=true; shift ;;
      --nvme)          USE_NVME=true; shift ;;
      --no-nvme)       USE_NVME=false; shift ;;
      --3d)            ENABLE_3D=true; shift ;;
      --no-3d)         ENABLE_3D=false; shift ;;
      --nested)        NESTED_VIRT=true; shift ;;
      --no-nested)     NESTED_VIRT=false; shift ;;
      --headless)      HEADLESS=true; START_MODE="headless"; shift ;;
      --gui)           HEADLESS=false; START_MODE="gui"; shift ;;
      --no-start)      START_MODE="none"; shift ;;
      --no-log)        LOG_FILE="/dev/null"; LOG_FILE_EXPLICIT=true; shift ;;
      --no-verify)     VERIFY=false; shift ;;
      --verify)        VERIFY=true; shift ;;
      --)              shift; break ;;
      --*=*)
        key="${arg%%=*}"; val="$(opt_value "$arg")"
        case "$key" in
          --iso) ISO_PATH="$val" ;;
          --name) VM_NAME="$val" ;;
          --preset) PRESET="$val" ;;
          --ostype) OSTYPE_OVERRIDE="$val" ;;
          --ram) RAM_MB="$val" ;;
          --cpus) CPUS="$val" ;;
          --disk) DISK_MB="$val" ;;
          --vram) VRAM_MB="$val" ;;
          --graphics) GRAPHICS="$val" ;;
          --firmware) FIRMWARE="$val" ;;
          --usb) USB_MODE="$val" ;;
          --tpm) TPM_TYPE="$val" ;;
          --secure-boot) SECURE_BOOT="$val" ;;
          --machine-folder) ACTIVE_MACHINE_FOLDER="$val" ;;
          --network) NETWORK_TYPE="$val" ;;
          --bridge-adapter) BRIDGE_ADAPTER="$val" ;;
          --hostonly-adapter) HOSTONLY_ADAPTER="$val" ;;
          --intnet-name) INTNET_NAME="$val" ;;
          --ssh-port) SSH_PORT="$val" ;;
          --forward) EXTRA_FORWARDS="${EXTRA_FORWARDS}${EXTRA_FORWARDS:+,}$val" ;;
          --shared-folder) SHARED_FOLDER="$val" ;;
          --shared-name) SHARED_NAME="$val" ;;
          --log-file) LOG_FILE="$val"; LOG_FILE_EXPLICIT=true ;;
          *) die_usage "Unknown option: $key" ;;
        esac
        shift
        ;;
      --iso|--name|--preset|--ostype|--ram|--cpus|--disk|--vram|--graphics|--firmware|--usb|--tpm|--secure-boot|--machine-folder|--network|--bridge-adapter|--hostonly-adapter|--intnet-name|--ssh-port|--forward|--shared-folder|--shared-name|--log-file)
        (( $# >= 2 )) || die_usage "Option $arg needs a value"
        key="$arg"; val="$2"
        case "$key" in
          --iso) ISO_PATH="$val" ;;
          --name) VM_NAME="$val" ;;
          --preset) PRESET="$val" ;;
          --ostype) OSTYPE_OVERRIDE="$val" ;;
          --ram) RAM_MB="$val" ;;
          --cpus) CPUS="$val" ;;
          --disk) DISK_MB="$val" ;;
          --vram) VRAM_MB="$val" ;;
          --graphics) GRAPHICS="$val" ;;
          --firmware) FIRMWARE="$val" ;;
          --usb) USB_MODE="$val" ;;
          --tpm) TPM_TYPE="$val" ;;
          --secure-boot) SECURE_BOOT="$val" ;;
          --machine-folder) ACTIVE_MACHINE_FOLDER="$val" ;;
          --network) NETWORK_TYPE="$val" ;;
          --bridge-adapter) BRIDGE_ADAPTER="$val" ;;
          --hostonly-adapter) HOSTONLY_ADAPTER="$val" ;;
          --intnet-name) INTNET_NAME="$val" ;;
          --ssh-port) SSH_PORT="$val" ;;
          --forward) EXTRA_FORWARDS="${EXTRA_FORWARDS}${EXTRA_FORWARDS:+,}$val" ;;
          --shared-folder) SHARED_FOLDER="$val" ;;
          --shared-name) SHARED_NAME="$val" ;;
          --log-file) LOG_FILE="$val"; LOG_FILE_EXPLICIT=true ;;
        esac
        shift 2
        ;;
      *) die_usage "Unknown option: $arg" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Resolution, validation, defaults
# ---------------------------------------------------------------------------
resolve_iso() {
  if [[ "$ISO_PATH" == "none" || -z "$ISO_PATH" ]]; then
    return 0
  fi
  [[ -f "$ISO_PATH" ]] || die "ISO not found: $ISO_PATH"
  # VirtualBox needs an absolute path; resolve relative ones.
  ISO_PATH="$(cd "$(dirname "$ISO_PATH")" && pwd)/$(basename "$ISO_PATH")"
  [[ -r "$ISO_PATH" ]] || die "ISO is not readable: $ISO_PATH"
}

# Ask for the ISO when it was not given (interactive) or fake it (dry run).
prompt_for_iso() {
  [[ -n "$ISO_PATH" ]] || {
    if $DRY_RUN; then
      ISO_PATH="/path/to/installer.iso"
      warn "No --iso given; using a placeholder for the dry run"
    elif [[ -t 0 ]]; then
      info "No ISO specified."
      read -r -p "ISO path (or 'none'): " ISO_PATH
      [[ -n "$ISO_PATH" ]] || die_usage "An ISO is required (or use --iso none)"
      resolve_iso
    else
      die_usage "An ISO is required in non-interactive mode (pass --iso PATH, or --iso none)"
    fi
  }
  return 0
}

# Derive and validate the VM name once the ISO is known.
resolve_vm_name() {
  if [[ -z "$VM_NAME" ]]; then
    if [[ -n "$ISO_PATH" && "$ISO_PATH" != "none" ]]; then
      VM_NAME="$(slugify "$(basename "$ISO_PATH")")"
    else
      VM_NAME="easyvbox-$(date +%Y%m%d-%H%M%S)"
    fi
  fi
  [[ "$VM_NAME" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die_usage "Invalid VM name '$VM_NAME' (allowed: letters, digits, dot, dash, underscore)"
}

slugify() {
  printf '%s' "$1" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-64
}

guess_ostype() {
  local filename lower
  filename="$(basename "$ISO_PATH")"
  lower="$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *win11*|*windows11*)                       echo "Windows11_64" ;;
    *win10*|*windows10*)                       echo "Windows10_64" ;;
    *win7*)                                    echo "Windows7_64" ;;
    *windows*)                                 echo "Windows10_64" ;;
    *ubuntu*)                                  echo "Ubuntu_64" ;;
    *mint*)                                    echo "Ubuntu_64" ;;
    *debian*)                                  echo "Debian_64" ;;
    *kali*)                                    echo "Debian_64" ;;
    *raspbian*)                                echo "Debian_64" ;;
    *fedora*)                                  echo "Fedora_64" ;;
    *rocky*|*alma*|*rhel*|*centos*)            echo "RedHat_64" ;;
    *arch*|*manjaro*|*endeavour*)              echo "ArchLinux_64" ;;
    *opensuse*|*suse*)                         echo "openSUSE_64" ;;
    *alpine*)                                  echo "Linux26_64" ;;
    *freebsd*)                                 echo "FreeBSD_64" ;;
    *openbsd*)                                 echo "OpenBSD_64" ;;
    *nixos*)                                   echo "Linux_64" ;;
    *)                                         echo "Linux_64" ;;
  esac
}

ostype_supported() { [[ -z "$VBOX_OSTYPES" ]] && return 0; printf '%s\n' "$VBOX_OSTYPES" | grep -qx "$1"; }

resolve_ostype() {
  local wanted fallback
  wanted="${OSTYPE_OVERRIDE:-$(guess_ostype)}"
  OSTYPE_WANTED="$wanted"
  if ostype_supported "$wanted"; then
    OSTYPE="$wanted"; return 0
  fi
  case "$wanted" in
    Windows11_64) fallback="Windows10_64" ;;
    *)            fallback="Linux_64" ;;
  esac
  if ostype_supported "$fallback"; then
    warn "OS type $wanted not supported by VirtualBox $VBOX_VERSION; using $fallback"
    OSTYPE="$fallback"; return 0
  fi
  warn "OS type $wanted not supported by this VirtualBox; using Linux_64"
  OSTYPE="Linux_64"
}

resolve_network() {
  [[ -n "$NETWORK_TYPE" ]] || NETWORK_TYPE="nat"
  case "$NETWORK_TYPE" in
    nat|bridged|hostonly|intnet|none) ;;
    bridge) NETWORK_TYPE="bridged" ;;
    *) die_usage "--network must be nat, bridged, hostonly, intnet or none (got: '$NETWORK_TYPE')" ;;
  esac
}

detect_bridge_adapter() {
  [[ "$NETWORK_TYPE" == "bridged" ]] || return 0
  if [[ -n "$BRIDGE_ADAPTER" && "$BRIDGE_ADAPTER" != "auto" ]]; then
    return 0
  fi
  BRIDGE_ADAPTER=""
  if [[ -n "$VBOX_BIN" ]]; then
    local available iface
    available="$("$VBOX_BIN" list bridgedifs 2>/dev/null | sed -n 's/^Name:[[:space:]]*//p')"
    if [[ "$HOST_OS" == "linux" && -r /proc/net/route ]]; then
      iface="$(awk '$2=="00000000" && $8=="0003" {print $1; exit}' /proc/net/route 2>/dev/null || true)"
      [[ -z "$iface" ]] && iface="$(ip route show default 2>/dev/null | awk '{print $5; exit}' || true)"
      if [[ -n "$iface" ]] && printf '%s\n' "$available" | grep -qx "$iface"; then
        BRIDGE_ADAPTER="$iface"
      fi
    elif [[ "$HOST_OS" == "macos" ]]; then
      iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"
      if [[ -n "$iface" ]] && printf '%s\n' "$available" | grep -qx "$iface"; then
        BRIDGE_ADAPTER="$iface"
      fi
    fi
    if [[ -z "$BRIDGE_ADAPTER" ]]; then
      if [[ -n "$available" ]]; then
        BRIDGE_ADAPTER="$(printf '%s\n' "$available" | head -n1)"
        warn "Could not detect the default network interface; using '$BRIDGE_ADAPTER'"
      else
        die "No bridged-capable network interface found on this host"
      fi
    else
      info "Bridged adapter: $BRIDGE_ADAPTER"
    fi
  else
    BRIDGE_ADAPTER="en0"
    warn "VirtualBox not found: assuming bridge adapter '$BRIDGE_ADAPTER' (dry run only)"
  fi
}

resolve_hostonly_adapter() {
  [[ "$NETWORK_TYPE" == "hostonly" ]] || return 0
  [[ -n "$HOSTONLY_ADAPTER" ]] && return 0
  [[ -n "$VBOX_BIN" ]] || { HOSTONLY_ADAPTER="vboxnet0"; return 0; }
  HOSTONLY_ADAPTER="$("$VBOX_BIN" list hostonlyifs 2>/dev/null | sed -n 's/^Name:[[:space:]]*//p' | sed -n '1p')"
  [[ -n "$HOSTONLY_ADAPTER" ]] || die "No host-only interface found. Create one: VBoxManage hostonlyif create"
}

resolve_intnet() {
  [[ "$NETWORK_TYPE" == "intnet" ]] || return 0
  [[ -n "$INTNET_NAME" ]] || INTNET_NAME="intnet"
}

apply_defaults() {
  # Smart defaults from host capacity when nothing else was specified.
  if [[ -z "$RAM_MB" ]]; then
    RAM_MB=$(( HOST_RAM_MB / 2 / 512 * 512 ))
    (( RAM_MB < 2048 )) && RAM_MB=2048
    (( RAM_MB > 16384 )) && RAM_MB=16384
  fi
  if [[ -z "$CPUS" ]]; then
    CPUS=$(( HOST_CPUS / 2 ))
    (( CPUS < 2 )) && CPUS=2
    (( CPUS > 8 )) && CPUS=8
  fi
  [[ -n "$DISK_MB" ]] || DISK_MB=40960
  [[ -n "$USE_NVME" ]] || USE_NVME=true
  [[ -n "$ENABLE_3D" ]] || ENABLE_3D=false
  [[ -n "$VRAM_MB" ]] || VRAM_MB=128
  [[ -n "$GRAPHICS" ]] || GRAPHICS="vmsvga"
  [[ -n "$FIRMWARE" ]] || FIRMWARE="efi"
  [[ -n "$USB_MODE" ]] || USB_MODE="ohci"
  [[ -n "$NESTED_VIRT" ]] || NESTED_VIRT=false
  [[ -n "$TPM_TYPE" ]] || TPM_TYPE="none"
  [[ -n "$SECURE_BOOT" ]] || SECURE_BOOT="off"
  [[ -n "$HEADLESS" ]] || HEADLESS=false
  [[ -n "$START_MODE" ]] || { if is_true "$HEADLESS"; then START_MODE="headless"; else START_MODE="gui"; fi; }
  [[ -n "$ACTIVE_MACHINE_FOLDER" ]] || ACTIVE_MACHINE_FOLDER="$DEFAULT_MACHINE_FOLDER"
  [[ -n "$ACTIVE_MACHINE_FOLDER" ]] || ACTIVE_MACHINE_FOLDER="$HOME/VirtualBox VMs"
  [[ -n "$SSH_PORT" ]] || SSH_PORT="2222"
}

normalize_sizes() {
  local parsed
  parsed="$(parse_size "$RAM_MB")" || die_usage "--ram must be a size like 4096 or 8G (got: '$RAM_MB')"
  RAM_MB="$parsed"
  parsed="$(parse_size "$DISK_MB")" || die_usage "--disk must be a size like 40960 or 60G (got: '$DISK_MB')"
  DISK_MB="$parsed"
  parsed="$(parse_size "$VRAM_MB")" || die_usage "--vram must be a number of MiB (got: '$VRAM_MB')"
  VRAM_MB="$parsed"
  if [[ "$CPUS" =~ ^[0-9]+$ ]]; then :; else
    die_usage "--cpus must be a number (got: '$CPUS')"
  fi
}

clamp_resources() {
  local max_ram max_cpus
  max_ram=$(( HOST_RAM_MB - 2048 ))
  (( max_ram < 1024 )) && max_ram=$(( HOST_RAM_MB * 3 / 4 ))
  (( max_ram < 512 )) && max_ram=512
  max_cpus="$HOST_CPUS"

  if (( RAM_MB > max_ram )); then
    if $FORCE_RESOURCES; then
      warn "Requested ${RAM_MB} MiB RAM exceeds safe capacity (${max_ram} MiB on this host) — continuing (--force-resources)"
    else
      max_ram=$(( max_ram / 128 * 128 ))
      (( max_ram < 512 )) && max_ram=512
      warn "Requested ${RAM_MB} MiB RAM is too much for this host; using ${max_ram} MiB"
      RAM_MB="$max_ram"
    fi
  fi
  if (( CPUS > max_cpus )); then
    if $FORCE_RESOURCES; then
      warn "Requested ${CPUS} CPUs exceeds host capacity ($max_cpus) — continuing (--force-resources)"
    else
      warn "Requested ${CPUS} CPUs exceeds host capacity; using ${max_cpus}"
      CPUS="$max_cpus"
    fi
  fi
}

validate_config() {
  require_positive_int "--ram"  "$RAM_MB"  256 1048576
  require_positive_int "--cpus" "$CPUS"    1   128
  require_positive_int "--disk" "$DISK_MB" 4096 16777216
  require_positive_int "--vram" "$VRAM_MB" 4   256
  (( RAM_MB % 4 == 0 )) || warn "RAM will be rounded by VirtualBox (requested ${RAM_MB} MiB)"

  case "$GRAPHICS" in
    vmsvga|vboxsvga|none) ;;
    *) die_usage "--graphics must be vmsvga, vboxsvga or none (got: '$GRAPHICS')" ;;
  esac
  case "$FIRMWARE" in
    efi|bios) ;;
    *) die_usage "--firmware must be efi or bios (got: '$FIRMWARE')" ;;
  esac
  USB_MODE="$(printf '%s' "$USB_MODE" | tr '[:upper:]' '[:lower:]')"
  case "$USB_MODE" in
    off|ohci|ehci|xhci) ;;
    on) USB_MODE="ohci" ;;
    *) die_usage "--usb must be off, ohci, ehci or xhci (got: '$USB_MODE')" ;;
  esac
  TPM_TYPE="$(printf '%s' "$TPM_TYPE" | tr '[:upper:]' '[:lower:]')"
  case "$TPM_TYPE" in
    none|1.2|2.0) ;;
    tpm2) TPM_TYPE="2.0" ;;
    *) die_usage "--tpm must be none or 2.0 (got: '$TPM_TYPE')" ;;
  esac
  SECURE_BOOT="$(printf '%s' "$SECURE_BOOT" | tr '[:upper:]' '[:lower:]')"
  case "$SECURE_BOOT" in
    on|true|yes|1) SECURE_BOOT="on" ;;
    off|false|no|0) SECURE_BOOT="off" ;;
    *) die_usage "--secure-boot must be on or off (got: '$SECURE_BOOT')" ;;
  esac

  if [[ "$TPM_TYPE" != "none" && "$VBOX_MAJOR" -lt 7 ]]; then
    if $VBOX_KNOWN; then
      die "TPM 2.0 requires VirtualBox 7.0 or newer (found: ${VBOX_VERSION}). Upgrade VirtualBox."
    else
      warn "TPM 2.0 needs VirtualBox 7.0+; cannot verify the installed version"
    fi
  fi
  if [[ "$SECURE_BOOT" == "on" && "$FIRMWARE" != "efi" ]]; then
    die_usage "Secure Boot requires EFI firmware (use --firmware efi)"
  fi
  if [[ "$SECURE_BOOT" == "on" && "$VBOX_MAJOR" -lt 7 ]] && $VBOX_KNOWN; then
    die "Secure Boot requires VirtualBox 7.0 or newer (found: ${VBOX_VERSION})"
  fi

  if [[ -n "$SSH_PORT" && "$SSH_PORT" != "none" ]]; then
    require_positive_int "--ssh-port" "$SSH_PORT" 1 65535
  fi

  # Rules apply when the guest is Windows 11, even if this VirtualBox build
  # only knows the Windows10_64 identifier.
  if [[ "$OSTYPE" == "Windows11_64" || "${OSTYPE_WANTED:-}" == "Windows11_64" ]]; then
    (( RAM_MB >= 4096 ))   || { warn "Windows 11 needs >= 4096 MiB RAM; raising"; RAM_MB=4096; }
    (( CPUS >= 2 ))        || { warn "Windows 11 needs >= 2 CPUs; raising"; CPUS=2; }
    (( DISK_MB >= 61440 )) || { warn "Windows 11 needs >= 64 GiB disk; raising"; DISK_MB=61440; }
    [[ "$FIRMWARE" == "efi" ]] || { warn "Windows 11 needs UEFI; switching to EFI"; FIRMWARE="efi"; }
    [[ "$TPM_TYPE" == "none" ]] && { warn "Windows 11 needs TPM 2.0; enabling"; TPM_TYPE="2.0"; }
    [[ "$SECURE_BOOT" == "off" ]] && { info "Windows 11: enabling Secure Boot (required by setup)"; SECURE_BOOT="on"; }
  fi

  if is_true "$ENABLE_3D" && [[ "$GRAPHICS" == "none" ]]; then
    die_usage "3D acceleration needs a graphics controller (--graphics vmsvga or vboxsvga)"
  fi
  if [[ "$TPM_TYPE" != "none" && "$FIRMWARE" != "efi" ]]; then
    warn "A virtual TPM 2.0 only works reliably with EFI firmware; consider --firmware efi"
  fi
  if is_true "$ENABLE_3D" && $VBOX_KNOWN && (( VBOX_MAJOR == 7 )) && (( VBOX_MINOR == 1 )); then
    warn "VirtualBox 7.1.x has known 3D acceleration regressions; use --no-3d if the guest fails to boot"
  fi
  if [[ "$USB_MODE" != "off" && "$USB_MODE" != "ohci" ]] && [[ -n "$VBOX_BIN" ]] && ! $HAS_EXTPACK; then
    warn "USB 2.0/3.0 needs the VirtualBox Extension Pack; falling back to USB 1.1"
    USB_MODE="ohci"
  fi
}

# Shared folder SPEC: [name=]PATH[:ro]
parse_shared_folder() {
  [[ -n "$SHARED_FOLDER" ]] || return 0
  local spec="$SHARED_FOLDER" path name
  if [[ "$spec" == *"="* ]]; then
    name="${spec%%=*}"
    path="${spec#*=}"
    [[ -n "$name" ]] && SHARED_NAME="$name"
    spec="$path"
  fi
  if [[ "$spec" == *":ro" ]]; then
    SHARED_RO=true
    spec="${spec%:ro}"
  fi
  [[ -n "$spec" ]] || die_usage "--shared-folder needs a path"
  # Expand ~ and make absolute
  # Expand a leading ~ ourselves (pattern matching keeps it literal).
  if [[ "$spec" == \~ || "$spec" == \~/* ]]; then
    spec="$HOME/${spec#\~}"
    spec="${spec%/}"
    spec="${spec:-$HOME}"
  fi
  if $DRY_RUN; then
    [[ -d "$spec" ]] && SHARED_FOLDER="$(cd "$spec" && pwd)" || SHARED_FOLDER="$spec"
    return 0
  fi
  mkdir -p "$spec" 2>/dev/null || die "Cannot create shared folder: $spec"
  SHARED_FOLDER="$(cd "$spec" && pwd)"
}

# ---------------------------------------------------------------------------
# Plan summary
# ---------------------------------------------------------------------------
print_config() {
  cat <<EOF
version=$VERSION
dry_run=$DRY_RUN
preset=${PRESET:-custom}
name=$VM_NAME
iso=${ISO_PATH:-none}
ostype=${OSTYPE:-auto}
ram_mb=$RAM_MB
cpus=$CPUS
disk_mb=$DISK_MB
vram_mb=$VRAM_MB
nvme=$USE_NVME
accelerate_3d=$ENABLE_3D
nested_virt=$NESTED_VIRT
graphics=$GRAPHICS
firmware=$FIRMWARE
tpm=$TPM_TYPE
secure_boot=$SECURE_BOOT
usb=$USB_MODE
network=$NETWORK_TYPE
ssh_port=${SSH_PORT:-none}
shared_folder=${SHARED_FOLDER:-none}
shared_name=${SHARED_NAME}
shared_readonly=$SHARED_RO
start=$START_MODE
machine_folder=$ACTIVE_MACHINE_FOLDER
vbox_version=$VBOX_VERSION
EOF
}

confirm_replace() {
  $ASSUME_YES && return 0
  [[ -t 0 ]] || die "VM '$VM_NAME' exists; pass --yes together with --replace to delete it"
  warn "This will DELETE the existing VM '$VM_NAME' and all its disks."
  local answer
  read -rp "Type the VM name to confirm deletion: " answer
  [[ "$answer" == "$VM_NAME" ]] || die "Confirmation failed; nothing was changed"
}

# ---------------------------------------------------------------------------
# Creation
# ---------------------------------------------------------------------------
create_vm() {
  local vm_dir disk_path

  if $DRY_RUN && vm_exists "$VM_NAME"; then
    warn "VM '$VM_NAME' already exists; a real run would need --replace"
  elif vm_exists "$VM_NAME"; then
    if $REPLACE; then
      confirm_replace
      info "Removing existing VM '$VM_NAME'"
      vbox unregistervm "$VM_NAME" --delete || die "Could not remove existing VM '$VM_NAME'"
    else
      die "VM '$VM_NAME' already exists. Use --name to choose another name, or --replace to recreate it."
    fi
  fi

  if ! $DRY_RUN; then
    mkdir -p "$ACTIVE_MACHINE_FOLDER" 2>/dev/null || die "Cannot create machine folder: $ACTIVE_MACHINE_FOLDER"
  fi

  info "Creating VM '$VM_NAME' ($OSTYPE) in $ACTIVE_MACHINE_FOLDER"
  vbox createvm --name "$VM_NAME" --ostype "$OSTYPE" --register --basefolder "$ACTIVE_MACHINE_FOLDER" \
    || die "VBoxManage createvm failed. See log: $LOG_FILE"
  VM_REGISTERED_BY_US=true

  # Ask VirtualBox where the VM actually lives (respects custom machine folders).
  vm_dir="$ACTIVE_MACHINE_FOLDER/$VM_NAME"
  if ! $DRY_RUN && [[ -n "$VBOX_BIN" ]]; then
    local cfg
    cfg="$("$VBOX_BIN" showvminfo "$VM_NAME" --machinereadable 2>/dev/null | sed -n 's/^CfgFile="\(.*\)"$/\1/p')"
    [[ -n "$cfg" ]] && vm_dir="$(dirname "$cfg")"
  fi

  # --- Hardware -------------------------------------------------------------
  # NOTE: --graphicscontroller must precede --accelerate-3d in the same call
  #       (VirtualBox issue #798), otherwise 3D setup fails on some versions.
  local args=(--memory "$RAM_MB" --cpus "$CPUS" --vram "$VRAM_MB"
              --graphicscontroller "$GRAPHICS" --firmware "$FIRMWARE"
              --ioapic on --nestedpaging on
              --clipboard-mode bidirectional --draganddrop bidirectional)
  local notes=()

  is_true "$USE_NVME" && notes+=("NVMe disk")
  is_true "$ENABLE_3D" && args+=(--accelerate-3d on)
  is_true "$NESTED_VIRT" && args+=(--nested-hw-virt on)

  case "$USB_MODE" in
    off)  args+=(--usb off) ;;
    ohci) args+=(--usb on) ;;
    ehci) args+=(--usb on --usbehci on) ;;
    xhci) args+=(--usb on --usbxhci on) ;;
  esac

  case "$NETWORK_TYPE" in
    nat)
      if [[ -n "$SSH_PORT" && "$SSH_PORT" != "none" ]]; then
        args+=(--nic1 nat --natpf1 "ssh,tcp,,${SSH_PORT},,22")
        notes+=("SSH localhost:${SSH_PORT}")
      else
        args+=(--nic1 nat)
      fi
      ;;
    bridged)  args+=(--nic1 bridged --bridgeadapter1 "$BRIDGE_ADAPTER") ;;
    hostonly) args+=(--nic1 hostonly --hostonlyadapter1 "$HOSTONLY_ADAPTER") ;;
    intnet)   args+=(--nic1 intnet --intnet1 "$INTNET_NAME") ;;
    none)     args+=(--nic1 none) ;;
  esac

  if [[ "$NETWORK_TYPE" == "nat" && -n "$EXTRA_FORWARDS" ]]; then
    local fwd n h g rest idx=2 old_ifs="$IFS"
    IFS=','
    for fwd in $EXTRA_FORWARDS; do
      IFS="$old_ifs"
      n="${fwd%%:*}"
      rest="${fwd#*:}"
      h="${rest%%:*}"
      g="${rest#*:}"
      if [[ "$fwd" != *:*:* || -z "$n" || -z "$h" || -z "$g" ]] \
         || [[ ! "$h" =~ ^[0-9]+$ || ! "$g" =~ ^[0-9]+$ ]]; then
        warn "Ignoring malformed forward '$fwd' (expected NAME:HOSTPORT:GUESTPORT)"
        IFS=','
        continue
      fi
      args+=(--natpf"$idx" "${n},tcp,,${h},,${g}")
      notes+=("${n} localhost:${h}")
      idx=$(( idx + 1 ))
      IFS=','
    done
    IFS="$old_ifs"
  fi

  if [[ "$TPM_TYPE" != "none" ]]; then
    args+=(--tpm-type "$TPM_TYPE")
  fi

  vbox modifyvm "$VM_NAME" "${args[@]}" || die "VBoxManage modifyvm failed. See log: $LOG_FILE"

  if [[ "$SECURE_BOOT" == "on" ]]; then
    # Supported directly on 7.x; fall back to NVRAM keys on builds that need it.
    if ! vbox modifyvm "$VM_NAME" --secure-boot on; then
      dry_note "VBoxManage modifynvram $VM_NAME secureboot --enable"
      warn "This VirtualBox build rejected --secure-boot; enrolling NVRAM keys instead"
      vbox_soft modifynvram "$VM_NAME" secureboot --enable
    fi
  fi

  # --- Storage --------------------------------------------------------------
  local disk_controller
  if is_true "$USE_NVME"; then
    disk_controller="NVMe"
    # NVMe lives on the PCIe bus and supports a single port.
    vbox storagectl "$VM_NAME" --name "NVMe" --add pcie --controller NVMe \
      --portcount 1 --bootable on || die "Could not create the NVMe controller"
    # NVMe cannot host optical drives, so SATA stays available for the
    # installer ISO (port 1) and Guest Additions (port 2).
    vbox storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci \
      --portcount 3 --bootable on || die "Could not create the SATA controller"
  else
    disk_controller="SATA"
    vbox storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci \
      --portcount 3 --bootable on || die "Could not create the SATA controller"
  fi

  disk_path="$vm_dir/$VM_NAME.vdi"
  vbox createmedium disk --filename "$disk_path" --size "$DISK_MB" \
    --variant Standard --format VDI || die "Could not create the virtual disk ($disk_path)"

  vbox storageattach "$VM_NAME" --storagectl "$disk_controller" --port 0 --device 0 \
    --type hdd --medium "$disk_path" --nonrotational on || die "Could not attach the virtual disk"
  local boot_desc="$disk_controller"

  if [[ -n "$ISO_PATH" && "$ISO_PATH" != "none" ]]; then
    vbox storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 \
      --type dvddrive --medium "$ISO_PATH" || die "Could not attach the ISO ($ISO_PATH)"
    vbox modifyvm "$VM_NAME" --boot1 dvd --boot2 disk || warn "Could not set the boot order"
    boot_desc="DVD, then disk"
  else
    vbox modifyvm "$VM_NAME" --boot1 disk --boot2 none || warn "Could not set the boot order"
    boot_desc="disk"
  fi

  # --- Shared folders -------------------------------------------------------
  if [[ -n "$SHARED_FOLDER" ]]; then
    if is_true "$SHARED_RO"; then
      vbox sharedfolder add "$VM_NAME" --name "$SHARED_NAME" --hostpath "$SHARED_FOLDER" \
        --automount --readonly || warn "Could not add the shared folder"
    else
      vbox sharedfolder add "$VM_NAME" --name "$SHARED_NAME" --hostpath "$SHARED_FOLDER" \
        --automount || warn "Could not add the shared folder"
    fi
    notes+=("share $SHARED_NAME=$SHARED_FOLDER")
  fi

  vbox modifyvm "$VM_NAME" --description \
    "EasyVbox v$VERSION | preset: ${PRESET:-custom} | created: $(date '+%F %T')" \
    || warn "Could not set the VM description"

  local verb="created"
  $DRY_RUN && verb="would be created"
  ! $DRY_RUN && CREATED_OK=true
  local disk_gib lines n
  disk_gib="$(awk -v m="$DISK_MB" 'BEGIN{printf "%.0f", m/1024}')"
  lines=(
    "OS:      $OSTYPE"
    "RAM:     ${RAM_MB} MiB"
    "CPUs:    $CPUS"
    "Disk:    ${disk_gib} GiB (dynamic VDI)"
    "Boot:    $boot_desc"
  )
  for n in "${notes[@]+"${notes[@]}"}"; do lines+=("Extras:  $n"); done
  printf '\n' >&2
  success "VM '$VM_NAME' $verb"
  printf '   %s\n' "${lines[@]}" >&2
}

# ---------------------------------------------------------------------------
# Post-creation verification
#
# Reads the configuration back from VirtualBox and compares it with what was
# requested. This catches options a given VirtualBox version silently ignores,
# which is the difference between "the commands looked right" and "the VM is
# actually configured this way". It never aborts a successful creation.
# ---------------------------------------------------------------------------
VMI=""                 # machinereadable dump of the VM
VCHECK_OK=0 VCHECK_WARN=0 VCHECK_SKIP=0
VCHECK_ISSUES=""

# Value of a "key=value" line (quotes stripped); empty when absent.
# VirtualBox quotes some keys ("NVMe-0-0"="...") and some values, so both the
# key and the value are normalised before comparing.
mi_field() {
  awk -v k="$2" '
    {
      if (index($0, k "=") == 1)                 { v = substr($0, length(k) + 2) }
      else if (index($0, "\"" k "\"=") == 1)    { v = substr($0, length(k) + 4) }
      else next
      gsub(/^"|"$/, "", v)
      print v
      exit
    }' "$1" 2>/dev/null
}
mi_has() {
  awk -v k="$2" '
    index($0, k "=") == 1 || index($0, "\"" k "\"=") == 1 { found = 1 }
    END { exit(found ? 0 : 1) }' "$1" 2>/dev/null
}
# First key among the arguments that this VirtualBox reports.
mi_first_key() {
  local f="$1"; shift
  local k
  for k in "$@"; do
    if mi_has "$f" "$k"; then printf '%s' "$k"; return 0; fi
  done
  return 1
}

vok()   { printf '   %b✓%b %s\n' "$GREEN" "$NC" "$*" >&2; VCHECK_OK=$(( VCHECK_OK + 1 )); }
vwarn() {
  printf '   %b⚠%b %s\n' "$YELLOW" "$NC" "$*" >&2
  VCHECK_WARN=$(( VCHECK_WARN + 1 ))
  VCHECK_ISSUES+="     - $*"$'\n'
}
vskip() { printf '   · %s (no lo informa esta versión de VirtualBox)\n' "$1" >&2; VCHECK_SKIP=$(( VCHECK_SKIP + 1 )); }

# vcheck <label> <expected> <key...>   (exact, case-sensitive)
vcheck() {
  local label="$1" want="$2"; shift 2
  local key got
  if ! key="$(mi_first_key "$VMI" "$@")"; then vskip "$label"; return 0; fi
  got="$(mi_field "$VMI" "$key")"
  if [[ "$got" == "$want" ]]; then vok "$label: $got"
  else vwarn "$label: se esperaba '$want' y se obtuvo '${got:-vacío}'"
  fi
}
# vcheck_ci <label> <expected> <key...>  (case-insensitive)
vcheck_ci() {
  local label="$1" want="$2"; shift 2
  local key got
  if ! key="$(mi_first_key "$VMI" "$@")"; then vskip "$label"; return 0; fi
  got="$(mi_field "$VMI" "$key")"
  if [[ "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" ]]; then
    vok "$label: $got"
  else
    vwarn "$label: se esperaba '$want' y se obtuvo '${got:-vacío}'"
  fi
}

verify_vm() {
  $DRY_RUN && return 0
  $VERIFY || return 0
  [[ -n "$VBOX_BIN" ]] || return 0

  info "Verifying the VM configuration"
  local dump
  dump="$("$VBOX_BIN" showvminfo "$VM_NAME" --machinereadable 2>/dev/null)" || dump=""
  if [[ -z "$dump" ]]; then
    vwarn "no se pudo leer la configuración con showvminfo"
    return 0
  fi
  VMI="$(mktemp 2>/dev/null || echo "$HOME/easyvbox-verify.$$")"
  printf '%s\n' "$dump" >"$VMI" 2>/dev/null || {
    warn "no se pudo guardar la configuración para verificarla"
    VMI=""
    return 0
  }

  # Hardware
  vcheck "memoria (MiB)" "$RAM_MB" memory memorysize
  vcheck "CPUs" "$CPUS" cpus
  vcheck "VRAM (MiB)" "$VRAM_MB" vram
  vcheck_ci "firmware" "$FIRMWARE" firmware
  vcheck_ci "gráficos" "$GRAPHICS" graphicscontroller graphics-controller
  vcheck_ci "3D" "$(is_true "$ENABLE_3D" && echo on || echo off)" accelerate3d accelerate-3d
  vcheck_ci "virtualización anidada" "$(is_true "$NESTED_VIRT" && echo on || echo off)" nested-hw-virt nested_hw_virt
  if [[ "$TPM_TYPE" != "none" ]]; then
    vcheck_ci "TPM" "$TPM_TYPE" tpm-type tpmtype
  fi
  if [[ "$SECURE_BOOT" == "on" ]]; then
    vcheck_ci "Secure Boot" on secure-boot secureboot
  fi
  case "$USB_MODE" in
    off)  vcheck_ci "USB" off usb ;;
    xhci) vcheck_ci "USB 3.0 (xHCI)" on usb-xhci usbxhci usb_xhci ;;
    ehci) vcheck_ci "USB 2.0 (EHCI)" on usb-ehci usbehci usb_ehci ;;
    ohci) vcheck_ci "USB" on usb ;;
  esac

  # Storage
  local i=0 ctype found_nvme=false found_sata=false
  while (( i < 8 )); do
    if ! mi_has "$VMI" "storagecontrollername$i"; then break; fi
    ctype="$(mi_field "$VMI" "storagecontrollertype$i")"
    case "$ctype" in
      NVMe) found_nvme=true ;;
      IntelAhci) found_sata=true ;;
    esac
    i=$(( i + 1 ))
  done
  if is_true "$USE_NVME"; then
    if $found_nvme; then vok "controladora NVMe presente"
    else vwarn "no se encontró la controladora NVMe"; fi
  fi
  if $found_sata; then vok "controladora SATA presente"
  else vwarn "no se encontró la controladora SATA"; fi

  local disk_ctl="SATA"
  is_true "$USE_NVME" && disk_ctl="NVMe"
  if mi_has "$VMI" "$disk_ctl-0-0"; then
    local medium
    medium="$(mi_field "$VMI" "$disk_ctl-0-0")"
    if [[ -n "$medium" && "$medium" != "none" ]]; then
      vok "disco en $disk_ctl puerto 0: $(basename "$medium")"
    else
      vwarn "no hay disco conectado en $disk_ctl puerto 0"
    fi
  else
    vskip "disco conectado"
  fi

  if [[ -n "$ISO_PATH" && "$ISO_PATH" != "none" ]]; then
    if mi_has "$VMI" "SATA-1-0"; then
      local dvd
      dvd="$(mi_field "$VMI" "SATA-1-0")"
      if [[ "$dvd" == "$ISO_PATH" ]]; then
        vok "ISO conectada: $(basename "$ISO_PATH")"
      else
        vwarn "la ISO conectada no es la esperada ('${dvd:-vacío}')"
      fi
    else
      vskip "ISO conectada"
    fi
    vcheck_ci "orden de arranque" "dvd" boot1
  else
    vcheck_ci "orden de arranque" "disk" boot1
  fi

  # Networking and sharing
  if [[ "$NETWORK_TYPE" == "nat" && -n "$SSH_PORT" && "$SSH_PORT" != "none" ]]; then
    if grep -qF ",tcp,,${SSH_PORT},,22" "$VMI" 2>/dev/null; then
      vok "SSH reenviado en el puerto $SSH_PORT"
    elif mi_has "$VMI" "Forwarding(0)"; then
      vwarn "no se encontró el reenvío SSH al puerto $SSH_PORT"
    else
      vskip "reenvío SSH"
    fi
  fi
  if [[ -n "$SHARED_FOLDER" ]]; then
    if grep -qE "^\"?SharedFolderNameHost\(0\)=\"?${SHARED_NAME}\"?$" "$VMI" 2>/dev/null; then
      vok "carpeta compartida '$SHARED_NAME' registrada"
    elif mi_has "$VMI" "SharedFolderNameHost(0)"; then
      vwarn "la carpeta compartida no se registró con el nombre '$SHARED_NAME'"
    else
      vwarn "no se encontró la carpeta compartida"
    fi
  fi

  log "VERIFY: ok=$VCHECK_OK warn=$VCHECK_WARN skip=$VCHECK_SKIP"
  local skipped=""
  (( VCHECK_SKIP > 0 )) && skipped=" · $VCHECK_SKIP sin datos"
  if (( VCHECK_WARN == 0 )); then
    success "Verificación correcta ($VCHECK_OK comprobaciones$skipped)"
  else
    warn "Verificación con avisos: $VCHECK_WARN ajuste(s) no aplicados, $VCHECK_OK correctos"
    printf '%s' "$VCHECK_ISSUES" >&2
    printf '   La VM existe y es usable; revisa estos ajustes en su configuración.\n' >&2
    printf '   Detalle completo: %s  ·  Oculta esta comprobación con --no-verify\n' "${LOG_FILE}" >&2
  fi
  rm -f "$VMI" 2>/dev/null || true
}

start_vm() {
  [[ "$START_MODE" == "none" ]] && { info "VM not started (--no-start). Start it with: VBoxManage startvm '$VM_NAME'" ; return 0; }

  info "Starting VM '$VM_NAME' ($START_MODE)"
  local rc=0
  if ! $DRY_RUN; then
    log "START: $START_MODE"
    "${VBOX_BIN:-VBoxManage}" startvm "$VM_NAME" --type "$START_MODE" >>"$LOG_FILE" 2>&1 || rc=$?
    if (( rc != 0 )); then
      warn "Could not start the VM (exit $rc). Common causes:"
      warn "  • CPU virtualization (VT-x/AMD-V) disabled in the BIOS/UEFI"
      warn "  • KVM/Hyper-V or another hypervisor is using the virtualization extensions"
      warn "  • The Extension Pack is missing for USB 3.0 (fixed automatically above)"
      [[ -n "$LOG_FILE" ]] && printf '  Full log: %s\n' "$LOG_FILE" >&2
      exit 1
    fi
    success "VM running ($START_MODE)"
  else
    printf 'VBoxManage startvm %q --type %q\n' "$VM_NAME" "$START_MODE"
  fi
}

show_disk_space_hint() {
  local folder="$1" avail
  while [[ ! -d "$folder" && "$folder" != "/" ]]; do folder="$(dirname "$folder")"; done
  [[ -d "$folder" ]] || return 0
  avail="$(df -Pm "$folder" 2>/dev/null | awk 'NR==2{print $4}' || true)"
  [[ "$avail" =~ ^[0-9]+$ ]] || return 0
  if (( avail < DISK_MB + 1024 )); then
    warn "Only ${avail} MiB free in $folder; the disk needs up to ${DISK_MB} MiB"
  fi
}

on_exit() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 )) && ! $CREATED_OK && $VM_REGISTERED_BY_US; then
    printf '\n' >&2
    warn "Setup did not finish; the VM '$VM_NAME' may be incomplete."
    warn "Remove it with: VBoxManage unregistervm '$VM_NAME' --delete"
    [[ -n "$LOG_FILE" && "$LOG_FILE" != "/dev/null" ]] && warn "Log: $LOG_FILE"
  fi
  exit $rc
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  log_init
  log "EasyVbox v$VERSION args: $(render_cmd "$@")"

  detect_host

  if find_vboxmanage; then
    VBOX_KNOWN=true
    vbox_version_info
    load_vbox_environment
    info "VirtualBox $VBOX_VERSION detected"
  else
    VBOX_BIN=""
    if $DRY_RUN || $PRINT_CONFIG; then
      warn "VirtualBox (VBoxManage) not found — showing the plan only"
    fi
  fi

  [[ -n "$PRESET" ]] && load_preset "$PRESET"

  # The ISO must be known before the OS type is guessed and the VM is named.
  resolve_iso
  prompt_for_iso

  apply_defaults
  normalize_sizes
  resolve_network
  resolve_ostype
  detect_bridge_adapter
  resolve_hostonly_adapter
  resolve_intnet
  validate_config
  clamp_resources
  parse_shared_folder
  resolve_vm_name

  if [[ -z "$VBOX_BIN" ]] && ! $DRY_RUN && ! $PRINT_CONFIG; then
    die "VirtualBox is not installed or VBoxManage is not in PATH. See docs/INSTALL.md"
  fi

  if [[ -n "$SSH_PORT" && "$SSH_PORT" != "none" && "$NETWORK_TYPE" == "nat" ]]; then
    local picked
    picked="$(pick_ssh_port "$SSH_PORT")"
    [[ "$picked" != "$SSH_PORT" ]] && info "Host port $SSH_PORT is in use; forwarding SSH on $picked instead"
    SSH_PORT="$picked"
  fi

  if $PRINT_CONFIG; then
    print_config
    exit 0
  fi

  if $DRY_RUN; then
    printf '# EasyVbox v%s — dry run plan (nothing will be changed)\n' "$VERSION"
    [[ -n "$PRESET" ]] && printf '# preset: %s\n' "$PRESET"
    printf '# vm: %s | iso: %s | ram: %s MiB | cpus: %s | disk: %s MiB\n' \
      "$VM_NAME" "$ISO_PATH" "$RAM_MB" "$CPUS" "$DISK_MB"
  else
    show_disk_space_hint "$ACTIVE_MACHINE_FOLDER"
    trap on_exit EXIT
  fi

  create_vm
  verify_vm
  start_vm
  trap - EXIT

  if ! $DRY_RUN; then
    printf '\n' >&2
    success "Done"
    printf '   VM folder: %s\n' "$ACTIVE_MACHINE_FOLDER/$VM_NAME" >&2
    printf '   Log:       %s\n' "$LOG_FILE" >&2
    printf '   Tip: install Guest Additions for clipboard, resizing and shared folders:\n' >&2
    printf '        ./scripts/install-guest-additions.sh --guest ubuntu\n' >&2
  fi
}

main "$@"
