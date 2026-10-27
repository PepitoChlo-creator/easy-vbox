#!/usr/bin/env bash
# Validate the JSON presets in presets/.
#
#   ./scripts/validate-presets.sh            # validate everything
#   ./scripts/validate-presets.sh dev kali   # validate specific presets
#
# Checks JSON syntax, required fields, value ranges and whether each preset is
# mentioned in README.md and docs/PRESETS.md (so docs never drift).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRESETS_DIR="${EASYVBOX_PRESETS_DIR:-$ROOT_DIR/presets}"

RED=''; GREEN=''; YELLOW=''; NC=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
fi

ERRORS=0
WARNINGS=0
CHECKED=0

err()  { printf '%b✗%b %s: %s\n' "$RED" "$NC" "$1" "$2"; ERRORS=$(( ERRORS + 1 )); }
warn() { printf '%b⚠%b %s: %s\n' "$YELLOW" "$NC" "$1" "$2"; WARNINGS=$(( WARNINGS + 1 )); }

# --- JSON tooling -----------------------------------------------------------
JSON_TOOL=""
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1; then
  JSON_TOOL="python3"
fi

flatten_json() {
  local file="$1"
  case "$JSON_TOOL" in
    jq) jq -r 'if type == "object" then to_entries[] | "\(.key)=\(.value)" else empty end' "$file" 2>/dev/null ;;
    python3)
      python3 - "$file" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception as exc:  # noqa: BLE001
    sys.stderr.write(str(exc) + "\n")
    sys.exit(1)
if not isinstance(data, dict):
    sys.stderr.write("top-level JSON value must be an object\n")
    sys.exit(1)
for key, value in data.items():
    if value is None:
        value = "null"
    elif isinstance(value, bool):
        value = "true" if value else "false"
    print(f"{key}={value}")
PY
      ;;
  esac
}

get_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n1; }

known_key() {
  case "$1" in
    schema|name|description|ram_mb|cpus|disk_mb|nvme|accelerate_3d|vram_mb|\
graphics_controller|firmware|tpm|secure_boot|nested_virt|usb|headless|shared_folder|\
port_forwards|tags) return 0 ;;
    *) return 1 ;;
  esac
}

check_int_range() {
  local label="$1" value="$2" min="$3" max="$4"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    err "$label" "must be an integer (got '$value')"; return
  fi
  if (( value < min || value > max )); then
    err "$label" "must be between $min and $max (got $value)"
  fi
}

check_bool() {
  local label="$1" value="$2"
  case "$value" in
    true|false) ;;
    *) err "$label" "must be true or false (got '$value')" ;;
  esac
}

check_enum() {
  local label="$1" value="$2"; shift 2
  local opt
  for opt in "$@"; do
    [[ "$value" == "$opt" ]] && return 0
  done
  err "$label" "invalid value '$value' (allowed: $*)"
}

validate_preset() {
  local file="$1" base name flat line key value
  base="$(basename "$file" .json)"
  CHECKED=$(( CHECKED + 1 ))

  if [[ -z "$JSON_TOOL" ]]; then
    warn "$base" "no jq or python3 found; skipping deep validation"
    return 0
  fi

  if ! flat="$(flatten_json "$file")"; then
    err "$base" "invalid JSON"
    return 0
  fi

  # Unknown keys usually mean a typo that would silently be ignored.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    known_key "$key" || err "$base" "unknown field '$key'"
  done <<<"$flat"

  name="$(get_field "$flat" name)"
  [[ -n "$name" ]] || err "$base" "missing 'name'"
  [[ -z "$name" || "$name" == "$base" ]] || err "$base" "name '$name' does not match the filename"

  [[ -n "$(get_field "$flat" description)" ]] || err "$base" "missing 'description'"

  value="$(get_field "$flat" schema)"
  [[ "$value" == "2" ]] || err "$base" "unsupported schema version '${value:-missing}' (expected 2)"

  check_int_range "$base ram_mb" "$(get_field "$flat" ram_mb)" 256 1048576
  check_int_range "$base cpus"   "$(get_field "$flat" cpus)"   1   128
  check_int_range "$base disk_mb" "$(get_field "$flat" disk_mb)" 4096 16777216

  value="$(get_field "$flat" vram_mb)"
  [[ -z "$value" ]] || check_int_range "$base vram_mb" "$value" 4 256

  check_bool "$base nvme"          "$(get_field "$flat" nvme)"
  check_bool "$base accelerate_3d" "$(get_field "$flat" accelerate_3d)"
  check_bool "$base nested_virt"   "$(get_field "$flat" nested_virt)"
  check_bool "$base headless"      "$(get_field "$flat" headless)"

  value="$(get_field "$flat" graphics_controller)"
  [[ -z "$value" ]] || check_enum "$base graphics_controller" "$value" vmsvga vboxsvga none
  value="$(get_field "$flat" firmware)"
  [[ -z "$value" ]] || check_enum "$base firmware" "$value" efi bios
  value="$(get_field "$flat" tpm)"
  [[ -z "$value" ]] || check_enum "$base tpm" "$value" none 2.0
  value="$(get_field "$flat" secure_boot)"
  [[ -z "$value" ]] || check_enum "$base secure_boot" "$value" on off
  value="$(get_field "$flat" usb)"
  [[ -z "$value" ]] || check_enum "$base usb" "$value" off ohci ehci xhci

  value="$(get_field "$flat" shared_folder)"
  case "$value" in
    ""|null|/*) ;;
    *) warn "$base" "shared_folder should be null or an absolute path (got '$value')" ;;
  esac

  # port_forwards: NAME:HOSTPORT:GUESTPORT[,NAME:HOSTPORT:GUESTPORT...]
  value="$(get_field "$flat" port_forwards)"
  if [[ -n "$value" && "$value" != "null" ]]; then
    local item rest fname host guest old_ifs="$IFS"
    IFS=','
    for item in $value; do
      IFS="$old_ifs"
      fname="${item%%:*}"
      rest="${item#*:}"
      host="${rest%%:*}"
      guest="${rest#*:}"
      if [[ -z "$fname" || ! "$host" =~ ^[0-9]+$ || ! "$guest" =~ ^[0-9]+$ ]]; then
        err "$base" "invalid port_forwards entry '$item' (expected NAME:HOSTPORT:GUESTPORT)"
      fi
      IFS=','
    done
    IFS="$old_ifs"
  fi

  # Secure Boot and TPM only make sense with EFI.
  local fw tpm sb
  fw="$(get_field "$flat" firmware)"
  tpm="$(get_field "$flat" tpm)"
  sb="$(get_field "$flat" secure_boot)"
  if [[ "$fw" == "bios" && ( "$tpm" == "2.0" || "$sb" == "on" ) ]]; then
    err "$base" "TPM 2.0 / Secure Boot require firmware 'efi'"
  fi
  if [[ "$sb" == "on" && "$tpm" != "2.0" ]]; then
    warn "$base" "Secure Boot is on but TPM is '$tpm' (Windows 11 needs tpm 2.0)"
  fi

  printf '%b✓%b %s\n' "$GREEN" "$NC" "$base"
}

# --- Docs coverage ----------------------------------------------------------
check_docs() {
  local name doc missing=0
  for doc in "$ROOT_DIR/README.md" "$ROOT_DIR/docs/PRESETS.md"; do
    [[ -f "$doc" ]] || continue
    while IFS= read -r file; do
      name="$(basename "$file" .json)"
      if ! grep -q "\`$name\`" "$doc" && ! grep -q "\b$name\b" "$doc"; then
        warn "$name" "not mentioned in ${doc#"$ROOT_DIR"/}"
        missing=$(( missing + 1 ))
      fi
    done < <(find "$PRESETS_DIR" -maxdepth 1 -name '*.json' | sort)
  done
  return 0
}

main() {
  local targets=() file
  if (( $# > 0 )); then
    for file in "$@"; do
      if [[ -f "$PRESETS_DIR/$file.json" ]]; then
        targets+=("$PRESETS_DIR/$file.json")
      else
        err "$file" "preset file not found"
      fi
    done
  else
    while IFS= read -r file; do targets+=("$file"); done \
      < <(find "$PRESETS_DIR" -maxdepth 1 -name '*.json' | sort)
  fi

  if (( ${#targets[@]} == 0 )); then
    printf '%b✗%b no presets found in %s\n' "$RED" "$NC" "$PRESETS_DIR"
    exit 1
  fi
  if [[ -z "$JSON_TOOL" ]]; then
    printf '%b⚠%b jq or python3 is required for full validation\n' "$YELLOW" "$NC"
  fi

  for file in "${targets[@]}"; do
    validate_preset "$file"
  done

  (( $# > 0 )) || check_docs

  printf '\n%d preset(s) checked — %d error(s), %d warning(s)\n' "$CHECKED" "$ERRORS" "$WARNINGS"
  (( ERRORS == 0 )) || exit 1
}

main "$@"
