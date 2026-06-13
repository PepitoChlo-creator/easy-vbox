#!/usr/bin/env bash
# EasyVbox v2.2 - Smart VirtualBox VM Creator
set -euo pipefail
VERSION="2.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESETS_DIR="$SCRIPT_DIR/../presets"
LOG_FILE="$HOME/easyvbox_$(date +%Y%m%d_%H%M%S).log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

VM_NAME="" ISO_PATH="" PRESET="" RAM_MB=0 CPUS=0 DISK_SIZE_MB=0 USE_NVME=false ENABLE_3D=false SHARED_FOLDER="" NETWORK_TYPE="nat" BRIDGE_ADAPTER="" HEADLESS=false DRY_RUN=false

log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }
die() { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}✓ $*${NC}"; }
info() { echo -e "${CYAN}▶ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }

check_deps() { command -v VBoxManage >/dev/null || die "VirtualBox not installed"; success "VirtualBox OK"; }
detect_resources() { local c r; c=$(nproc 2>/dev/null || echo 4); r=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 8192); SUGGESTED_CPUS=$((c/2)); [[ $SUGGESTED_CPUS -lt 2 ]] && SUGGESTED_CPUS=2; SUGGESTED_RAM=$((r/2)); [[ $SUGGESTED_RAM -lt 2048 ]] && SUGGESTED_RAM=2048; SUGGESTED_DISK=61440; }

load_preset() {
  local f="$PRESETS_DIR/$1.json"; [[ -f "$f" ]] || die "Preset not found: $1"
  info "Loading preset $1"
  if command -v jq >/dev/null; then
    RAM_MB=$(jq -r '.ram_mb//4096' "$f"); CPUS=$(jq -r '.cpus//2' "$f"); DISK_SIZE_MB=$(jq -r '.disk_mb//40960' "$f")
    USE_NVME=$(jq -r '.nvme//false' "$f"); ENABLE_3D=$(jq -r '.accelerate_3d//false' "$f")
    [[ "$(jq -r '.headless//false' "$f")" == "true" ]] && HEADLESS=true
  else
    RAM_MB=$(grep -o '"ram_mb":[0-9]*' "$f" | head -1 | grep -o '[0-9]*' || echo 4096)
    CPUS=$(grep -o '"cpus":[0-9]*' "$f" | head -1 | grep -o '[0-9]*' || echo 2)
    DISK_SIZE_MB=$(grep -o '"disk_mb":[0-9]*' "$f" | head -1 | grep -o '[0-9]*' || echo 40960)
    grep -q '"nvme":true' "$f" && USE_NVME=true; grep -q '"accelerate_3d":true' "$f" && ENABLE_3D=true
  fi
  success "Preset loaded"
}

list_presets() { echo "Available presets:"; for f in "$PRESETS_DIR"/*.json; do [[ -f "$f" ]] || continue; n=$(basename "$f" .json); d=$(grep -o '"description":"[^"]*"' "$f" | cut -d'"' -f4 || echo ""); printf "  %-15s %s\n" "$n" "$d"; done; }

select_iso() { [[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] && return; info "Select ISO"; if command -v zenity >/dev/null; then ISO_PATH=$(zenity --file-selection --title="ISO" --file-filter="*.iso" 2>/dev/null || true); fi; [[ -z "$ISO_PATH" ]] && read -e -rp "ISO path: " ISO_PATH; [[ -f "$ISO_PATH" ]] || die "Bad ISO"; success "ISO OK"; }

detect_ostype() { local l=$(basename "$ISO_PATH" | tr '[:upper:]' '[:lower:]'); case "$l" in *win11*) OSTYPE="Windows11_64";; *win10*) OSTYPE="Windows10_64";; *ubuntu*|*mint*) OSTYPE="Ubuntu_64";; *debian*) OSTYPE="Debian_64";; *fedora*) OSTYPE="Fedora_64";; *arch*|*manjaro*) OSTYPE="ArchLinux_64";; *kali*) OSTYPE="Debian_64";; *) OSTYPE="Linux_64";; esac; }

create_vm() {
  [[ -z "$VM_NAME" ]] && VM_NAME=$(basename "$ISO_PATH" | sed 's/\.[^.]*$//' | tr ' ' '_' | tr -cd '[:alnum:]_-' | cut -c1-40)
  VBoxManage list vms | grep -q "\"$VM_NAME\"" && die "VM exists"
  detect_ostype; info "OS: $OSTYPE"
  if [[ "$OSTYPE" == "Windows11_64" ]]; then [[ $RAM_MB -lt 4096 ]] && RAM_MB=4096; [[ $DISK_SIZE_MB -lt 61440 ]] && DISK_SIZE_MB=61440; warn "Win11 → TPM+SecureBoot"; fi

  local p="$HOME/VirtualBox VMs/$VM_NAME"; mkdir -p "$p"
  VBoxManage createvm --name "$VM_NAME" --ostype "$OSTYPE" --register --basefolder "$HOME/VirtualBox VMs" >>"$LOG_FILE" 2>&1

  local args=(--memory "$RAM_MB" --cpus "$CPUS" --vram 128 --ioapic on --pae on --longmode on --nestedpaging on --firmware efi --clipboard-mode bidirectional --draganddrop bidirectional --usb on --usbehci on --usbxhci on)
  if [[ "$NETWORK_TYPE" == "bridged" ]]; then args+=(--nic1 bridged --bridgeadapter1 "${BRIDGE_ADAPTER:-enp0s3}"); else args+=(--nic1 nat --natpf1 "ssh,tcp,,2222,,22"); fi
  [[ "$OSTYPE" == "Windows11_64" ]] && args+=(--tpm 2.0 --secure-boot on); $ENABLE_3D && args+=(--accelerate3d on)
  VBoxManage modifyvm "$VM_NAME" "${args[@]}" >>"$LOG_FILE" 2>&1

  local ctrl="SATA Controller" typ="IntelAhci"; $USE_NVME && { ctrl="NVMe Controller"; typ="NVMe"; }
  VBoxManage storagectl "$VM_NAME" --name "$ctrl" --add "$(echo $typ | tr 'A-Z' 'a-z')" --controller "$typ" --portcount 4 --bootable on >>"$LOG_FILE" 2>&1

  local d="$p/$VM_NAME.vdi"; VBoxManage createhd --filename "$d" --size "$DISK_SIZE_MB" --variant Standard >>"$LOG_FILE" 2>&1
  VBoxManage storageattach "$VM_NAME" --storagectl "$ctrl" --port 0 --device 0 --type hdd --medium "$d" >>"$LOG_FILE" 2>&1
  VBoxManage storageattach "$VM_NAME" --storagectl "$ctrl" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH" >>"$LOG_FILE" 2>&1
  VBoxManage modifyvm "$VM_NAME" --boot1 dvd --boot2 disk >>"$LOG_FILE" 2>&1

  [[ -n "$SHARED_FOLDER" ]] && { mkdir -p "$SHARED_FOLDER"; VBoxManage sharedfolder add "$VM_NAME" --name "HostShare" --hostpath "$SHARED_FOLDER" --automount >>"$LOG_FILE" 2>&1; success "Shared folder ready"; }

  VBoxManage modifyvm "$VM_NAME" --description "EasyVbox v$VERSION | Preset: ${PRESET:-custom}" >>"$LOG_FILE" 2>&1
  success "VM '$VM_NAME' created"
}

start_vm() { local m="gui"; $HEADLESS && m="headless"; VBoxManage startvm "$VM_NAME" --type "$m" >>"$LOG_FILE" 2>&1 || true; success "Started"; }

parse_args() {
  while [[ $# -gt 0 ]]; do case "$1" in
    --iso) ISO_PATH="$2"; shift 2;; --name) VM_NAME="$2"; shift 2;; --preset) PRESET="$2"; shift 2;;
    --ram) RAM_MB="$2"; shift 2;; --cpus) CPUS="$2"; shift 2;; --disk) DISK_SIZE_MB="$2"; shift 2;;
    --nvme) USE_NVME=true; shift;; --3d) ENABLE_3D=true; shift;;
    --shared-folder) SHARED_FOLDER="$2"; shift 2;; --network) NETWORK_TYPE="$2"; shift 2;;
    --bridge-adapter) BRIDGE_ADAPTER="$2"; shift 2;; --headless) HEADLESS=true; shift;;
    --dry-run) DRY_RUN=true; shift;; --list-presets) list_presets; exit 0;; --help) echo "See README"; exit 0;;
    *) die "Bad option $1";;
  esac; done
}

main() {
  touch "$LOG_FILE"; parse_args "$@"; check_deps; detect_resources
  [[ -n "$PRESET" ]] && load_preset "$PRESET"
  [[ -z "$ISO_PATH" && $RAM_MB -eq 0 ]] && { select_iso; list_presets; read -rp "Preset: " PRESET; [[ -n "$PRESET" ]] && load_preset "$PRESET"; }
  [[ -z "$ISO_PATH" ]] && die "Need --iso"
  [[ ! -f "$ISO_PATH" ]] && die "ISO missing"
  if $DRY_RUN; then echo "DRY: $ISO_PATH preset=${PRESET:-custom} ram=$RAM_MB cpus=$CPUS disk=$DISK_SIZE_MB nvme=$USE_NVME 3d=$ENABLE_3D net=$NETWORK_TYPE"; exit 0; fi
  create_vm; [[ "${START_MODE:-gui}" != "none" ]] && start_vm
  echo "Tip: ./scripts/install-guest-additions.sh for best results inside guest"; success "Done. Log: $LOG_FILE"
}
main "$@"
