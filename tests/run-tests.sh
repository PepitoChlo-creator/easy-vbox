#!/usr/bin/env bash
# EasyVbox test suite.
#
# Runs scripts/create-vm.sh against a fake VBoxManage (tests/mock/VBoxManage),
# so the complete VM-creation flow is verified without VirtualBox installed.
#
#   ./tests/run-tests.sh              # run everything
#   ./tests/run-tests.sh -v           # verbose (show each command)
#   ./tests/run-tests.sh test_dry_run # run one test by name
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/create-vm.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-presets.sh"
MOCK_DIR="$ROOT_DIR/tests/mock"

RED=''; GREEN=''; CYAN=''; NC=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
fi

PASS=0
FAIL=0
TEST_FAILED=0
FAILED_TESTS=()
VERBOSE=0
OUT=""
ERR=""
RC=0

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
setup() {
  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/easyvbox-test.XXXXXX")"
  TEST_TMP_CANON="$(cd "$TEST_TMP" && pwd)"
  export MOCK_STATE="$TEST_TMP/state"
  export MOCK_LOG="$MOCK_STATE/calls.log"
  mkdir -p "$MOCK_STATE" "$TEST_TMP/home" "$TEST_TMP/project"
  export HOME="$TEST_TMP/home"
  export PATH="$MOCK_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  export NO_COLOR=1
  export EASYVBOX_HOST_RAM_MB=32768
  export EASYVBOX_HOST_CPUS=16
  unset VBOXMANAGE MOCK_EXTPACK MOCK_BRIDGED MOCK_VERSION MOCK_FAIL_ON MOCK_OSTYPES_LIST
  : >"$MOCK_LOG"
  ISO="$TEST_TMP/fake.iso"
  : >"$ISO"
  WIN_ISO="$TEST_TMP/win11.iso"
  : >"$WIN_ISO"
}

teardown() { [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"; }

hide_vbox() { export VBOXMANAGE="$TEST_TMP/definitely-not-vboxmanage"; }
use_mock()  { unset VBOXMANAGE; }

run_cli() {
  if (( VERBOSE )); then printf '  $ %s %s\n' "$SCRIPT" "$*"; fi
  OUT="$("$SCRIPT" "$@" 2>"$TEST_TMP/stderr" </dev/null)"
  RC=$?
  ERR="$(cat "$TEST_TMP/stderr" 2>/dev/null || true)"
  if (( VERBOSE )); then
    printf '  rc=%s\n' "$RC"
    printf '%s\n' "$OUT" | sed 's/^/  out| /'
    printf '%s\n' "$ERR" | sed 's/^/  err| /'
  fi
}

fail() {
  printf '  %b✗%b %s\n' "$RED" "$NC" "$*"
  TEST_FAILED=1
}

assert_rc() {
  [[ "$RC" == "$1" ]] || fail "exit code: expected $1, got $RC (stderr: $ERR)"
}
assert_contains() {
  local what="$1" needle="$2" hay="$3"
  [[ "$hay" == *"$needle"* ]] || fail "$what: expected to contain '$needle'"
}
assert_not_contains() {
  local what="$1" needle="$2" hay="$3"
  [[ "$hay" != *"$needle"* ]] || fail "$what: did not expect '$needle'"
}
assert_file()      { [[ -f "$1" ]] || fail "expected file to exist: $1"; }
assert_no_file()   { [[ ! -e "$1" ]] || fail "expected path NOT to exist: $1"; }
assert_log()       { grep -qF -- "$1" "$MOCK_LOG" || fail "mock log should contain: $1"; }
assert_no_log()    { if grep -qF -- "$1" "$MOCK_LOG"; then fail "mock log should NOT contain: $1"; fi; }
assert_log_line()  { grep -qxF -- "$1" "$MOCK_LOG" || fail "mock log should have line: $1"; }

run_test() {
  local fn="$1"
  TEST_FAILED=0
  setup
  "$fn"
  teardown
  if (( TEST_FAILED )); then
    FAIL=$(( FAIL + 1 ))
    FAILED_TESTS+=("$fn")
    printf '%b✗ %s%b\n' "$RED" "$fn" "$NC"
  else
    PASS=$(( PASS + 1 ))
    printf '%b✓%b %s\n' "$GREEN" "$NC" "$fn"
  fi
}

seed_vm() {
  local name="$1"
  printf '%s\n' "$name" >>"$MOCK_STATE/vms"
  mkdir -p "$MOCK_STATE/forwarding"
}

# ---------------------------------------------------------------------------
# CLI basics (no VirtualBox required)
# ---------------------------------------------------------------------------
test_help_without_vbox() {
  hide_vbox
  run_cli --help
  assert_rc 0
  assert_contains "help" "USAGE" "$OUT"
  assert_contains "help" "--preset" "$OUT"
  assert_no_file "$HOME/.easyvbox"
}

test_version() {
  hide_vbox
  run_cli --version
  assert_rc 0
  assert_contains "version" "easy-vbox 3.0.0" "$OUT"
}

test_list_presets_without_vbox() {
  hide_vbox
  run_cli --list-presets
  assert_rc 0
  assert_contains "list" "PRESET" "$OUT"
  local count
  count="$(printf '%s\n' "$OUT" | tail -n +2 | grep -c . || true)"
  [[ "$count" == "12" ]] || fail "expected 12 presets, got $count"
  assert_contains "list" "windows11" "$OUT"
  assert_contains "list" "minimal-testing" "$OUT"
}

test_unknown_option() {
  run_cli --definitely-not-an-option
  assert_rc 2
  assert_contains "error" "Unknown option" "$ERR"
}

test_missing_iso_non_interactive() {
  run_cli --preset dev
  assert_rc 2
  assert_contains "error" "ISO" "$ERR"
}

test_unknown_preset() {
  run_cli --iso "$ISO" --preset nope
  assert_rc 2
  assert_contains "error" "Preset not found" "$ERR"
}

test_invalid_ram() {
  run_cli --iso "$ISO" --ram abc
  assert_rc 2
  assert_contains "error" "--ram" "$ERR"
}

test_invalid_vm_name() {
  run_cli --iso "$ISO" --name "bad name!"
  assert_rc 2
  assert_contains "error" "Invalid VM name" "$ERR"
}

test_size_units() {
  hide_vbox
  run_cli --iso "$ISO" --ram 8G --disk 64G --print-config
  assert_rc 0
  assert_contains "units" "ram_mb=8192" "$OUT"
  assert_contains "units" "disk_mb=65536" "$OUT"
}

test_preset_values() {
  hide_vbox
  run_cli --iso "$ISO" --preset dev --print-config
  assert_rc 0
  assert_contains "preset" "ram_mb=8192" "$OUT"
  assert_contains "preset" "cpus=4" "$OUT"
  assert_contains "preset" "disk_mb=61440" "$OUT"
  assert_contains "preset" "nvme=true" "$OUT"
  assert_contains "preset" "tpm=none" "$OUT"
  assert_contains "preset" "accelerate_3d=true" "$OUT"
}

test_cli_overrides_preset() {
  hide_vbox
  run_cli --iso "$ISO" --preset gaming --ram 4096 --cpus 2 --no-3d --ram 4096 --print-config
  assert_rc 0
  assert_contains "override" "ram_mb=4096" "$OUT"
  assert_contains "override" "cpus=2" "$OUT"
  assert_contains "override" "accelerate_3d=false" "$OUT"
  assert_not_contains "override" "ram_mb=16384" "$OUT"
}

test_clamp_resources() {
  hide_vbox
  export EASYVBOX_HOST_RAM_MB=8192 EASYVBOX_HOST_CPUS=4
  run_cli --iso "$ISO" --ram 16384 --cpus 16 --print-config
  assert_rc 0
  assert_contains "clamp" "ram_mb=6144" "$OUT"
  assert_contains "clamp" "cpus=4" "$OUT"
  assert_contains "clamp" "too much" "$ERR"
}

test_force_resources() {
  hide_vbox
  export EASYVBOX_HOST_RAM_MB=8192
  run_cli --iso "$ISO" --ram 16384 --force-resources --print-config
  assert_rc 0
  assert_contains "force" "ram_mb=16384" "$OUT"
}

test_relative_iso_becomes_absolute() {
  hide_vbox
  OUT="$(cd "$TEST_TMP" && "$SCRIPT" --iso ./fake.iso --print-config 2>"$TEST_TMP/stderr" </dev/null)"
  RC=$?
  ERR="$(cat "$TEST_TMP/stderr")"
  assert_rc 0
  assert_contains "iso" "iso=$TEST_TMP_CANON/fake.iso" "$OUT"
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------
test_dry_run_without_vbox() {
  hide_vbox
  run_cli --iso "$ISO" --preset dev --dry-run
  assert_rc 0
  assert_contains "plan" "dry run plan" "$OUT"
  assert_contains "plan" "createvm" "$OUT"
  assert_contains "plan" "modifyvm" "$OUT"
  assert_contains "plan" "storageattach" "$OUT"
  assert_no_file "$HOME/VirtualBox VMs"
}

test_dry_run_without_iso() {
  hide_vbox
  run_cli --preset server --dry-run
  assert_rc 0
  assert_contains "plan" "installer.iso" "$OUT"
  assert_contains "warning" "placeholder" "$ERR"
}

test_dry_run_uses_valid_nvme_syntax() {
  use_mock
  run_cli --iso "$ISO" --preset dev --dry-run
  assert_rc 0
  assert_contains "nvme" "--add pcie --controller NVMe --portcount 1" "$OUT"
  assert_contains "dvd" "--type dvddrive" "$OUT"
  assert_no_log "createvm"
}

# ---------------------------------------------------------------------------
# Real creation flow (against the mock)
# ---------------------------------------------------------------------------
test_full_create_dev() {
  use_mock
  run_cli --iso "$ISO" --preset dev --name devvm
  assert_rc 0
  assert_contains "log" "createvm --name devvm" "$(cat "$MOCK_LOG")"
  assert_log "--add pcie --controller NVMe --portcount 1"
  assert_log "--storagectl NVMe --port 0 --device 0 --type hdd"
  assert_log "--storagectl SATA --port 1 --device 0 --type dvddrive"
  assert_log "--natpf1 ssh,tcp,,2222,,22"
  assert_log "--firmware efi"
  assert_log "--accelerate-3d on"
  assert_log "startvm devvm --type gui"
  assert_file "$MOCK_STATE/VirtualBox VMs/devvm/devvm.vdi"
  assert_file "$MOCK_STATE/started/devvm"
  assert_contains "created" "VM 'devvm' created" "$ERR"
}

test_no_nvme_uses_sata() {
  use_mock
  run_cli --iso "$ISO" --name satavm --no-nvme --no-3d
  assert_rc 0
  assert_log "storagectl satavm --name SATA --add sata --controller IntelAhci"
  assert_log "--storagectl SATA --port 0 --device 0 --type hdd"
  assert_log "--storagectl SATA --port 1 --device 0 --type dvddrive"
  assert_no_log "NVMe"
}

test_iso_none_skips_dvd() {
  use_mock
  run_cli --iso none --name blankvm --preset minimal-testing
  assert_rc 0
  assert_no_log "dvddrive"
  assert_log "--boot1 disk"
  assert_file "$MOCK_STATE/VirtualBox VMs/blankvm/blankvm.vdi"
}

test_headless_and_no_start() {
  use_mock
  run_cli --iso "$ISO" --name hvm --headless
  assert_rc 0
  assert_log "startvm hvm --type headless"

  : >"$MOCK_LOG"
  run_cli --iso "$ISO" --name nsvm --no-start
  assert_rc 0
  assert_no_log "startvm nsvm"
  assert_contains "hint" "not started" "$ERR"
}

test_windows11_requirements() {
  use_mock
  run_cli --iso "$WIN_ISO" --preset windows11 --name winvm
  assert_rc 0
  local log
  log="$(cat "$MOCK_LOG")"
  assert_contains "ostype" "--ostype Windows11_64" "$log"
  assert_contains "tpm" "--tpm-type 2.0" "$log"
  assert_contains "secureboot" "--secure-boot on" "$log"
  assert_contains "efi" "--firmware efi" "$log"
  assert_contains "disk" "--size 131072" "$log"
  assert_contains "mem" "--memory 8192" "$log"
}

test_tpm_requires_vbox7() {
  use_mock
  export MOCK_VERSION=6.1.50r161033
  run_cli --iso "$WIN_ISO" --preset windows11
  assert_rc 1
  assert_contains "error" "VirtualBox 7" "$ERR"
  assert_no_log "createvm"
}

test_secure_boot_fallback() {
  use_mock
  export MOCK_FAIL_ON="--secure-boot on"
  run_cli --iso "$WIN_ISO" --preset windows11 --name w11fb
  assert_rc 0
  assert_log "modifynvram w11fb secureboot --enable"
  assert_contains "warning" "NVRAM" "$ERR"
}

test_usb_falls_back_without_extpack() {
  use_mock
  run_cli --iso "$ISO" --preset dev --name usb1
  assert_rc 0
  assert_log "--usb on"
  assert_no_log "--usbxhci on"
  assert_contains "warning" "Extension Pack" "$ERR"
}

test_usb_xhci_with_extpack() {
  use_mock
  export MOCK_EXTPACK=1
  run_cli --iso "$ISO" --preset dev --name usb2
  assert_rc 0
  assert_log "--usbxhci on"
}

test_ssh_port_collision() {
  use_mock
  seed_vm existing
  printf 'ssh,tcp,,2222,,22\n' >"$MOCK_STATE/forwarding/existing"
  run_cli --iso "$ISO" --name portvm
  assert_rc 0
  assert_log "--natpf1 ssh,tcp,,2223,,22"
  assert_contains "port" "2223" "$ERR"
}

test_extra_forward_from_preset() {
  use_mock
  run_cli --iso "$ISO" --preset fullstack --name webvm
  assert_rc 0
  assert_log "--natpf2 http,tcp,,8080,,80"
  assert_log "--natpf3 https,tcp,,8443,,443"
}

test_cli_forward() {
  use_mock
  run_cli --iso "$ISO" --name fwdvm --forward admin:9000:9000
  assert_rc 0
  assert_log "--natpf2 admin,tcp,,9000,,9000"
}

test_shared_folder() {
  use_mock
  run_cli --iso "$ISO" --name sharevm --shared-folder "src=$TEST_TMP/project"
  assert_rc 0
  assert_log "sharedfolder add sharevm --name src --hostpath $TEST_TMP_CANON/project --automount"
  assert_no_log "--readonly"
}

test_shared_folder_readonly_and_tilde() {
  use_mock
  run_cli --iso "$ISO" --name rov --shared-folder "$TEST_TMP/project:ro"
  assert_rc 0
  assert_log "--hostpath $TEST_TMP_CANON/project --automount --readonly"
}

test_existing_vm_is_refused() {
  use_mock
  seed_vm devvm
  run_cli --iso "$ISO" --name devvm
  assert_rc 1
  assert_contains "error" "already exists" "$ERR"
  assert_no_log "createvm"
}

test_replace_requires_confirmation() {
  use_mock
  seed_vm devvm
  run_cli --iso "$ISO" --name devvm --replace
  assert_rc 1
  assert_contains "error" "--yes" "$ERR"
  assert_no_log "unregistervm"
}

test_replace_with_yes() {
  use_mock
  seed_vm devvm
  run_cli --iso "$ISO" --name devvm --replace --yes
  assert_rc 0
  assert_log "unregistervm devvm --delete"
  assert_log "createvm --name devvm"
}

test_bridged_autodetect() {
  use_mock
  export MOCK_BRIDGED=1
  run_cli --iso "$ISO" --name bridgedvm --network bridged
  assert_rc 0
  assert_log "--nic1 bridged --bridgeadapter1 eth0"
  assert_contains "bridge" "eth0" "$ERR"
}

test_network_alias_bridge() {
  use_mock
  export MOCK_BRIDGED=1
  run_cli --iso "$ISO" --name aliasvm --network bridge --bridge-adapter eth1
  assert_rc 0
  assert_log "--nic1 bridged --bridgeadapter1 eth1"
}

test_invalid_network() {
  run_cli --iso "$ISO" --network banana
  assert_rc 2
  assert_contains "error" "--network" "$ERR"
}

test_ostype_fallback() {
  use_mock
  export MOCK_OSTYPES_LIST="Linux_64,Ubuntu_64"
  export EASYVBOX_HOST_RAM_MB=6144   # default RAM 3072 -> Win11 must raise it to 4096
  run_cli --iso "$WIN_ISO" --name fallbackvm
  assert_rc 0
  assert_log "--ostype Linux_64"
  assert_contains "warning" "not supported" "$ERR"
  # Windows 11 requirements still apply even when the ostype had to fall back.
  assert_log "--tpm-type 2.0"
  assert_log "--secure-boot on"
  assert_log "--memory 4096"
}

test_partial_failure_gives_cleanup_hint() {
  use_mock
  export MOCK_FAIL_ON="--type dvddrive"
  run_cli --iso "$ISO" --name brokervm
  assert_rc 1
  assert_contains "hint" "may be incomplete" "$ERR"
  assert_contains "hint" "unregistervm 'brokervm' --delete" "$ERR"
}

test_existing_vm_has_no_cleanup_hint() {
  use_mock
  seed_vm devvm
  run_cli --iso "$ISO" --name devvm
  assert_rc 1
  assert_contains "error" "already exists" "$ERR"
  assert_not_contains "hint" "may be incomplete" "$ERR"
}

test_print_config_without_vbox_windows11() {
  hide_vbox
  run_cli --iso "$WIN_ISO" --preset windows11 --print-config
  assert_rc 0
  assert_contains "config" "tpm=2.0" "$OUT"
  assert_contains "config" "secure_boot=on" "$OUT"
}

test_verify_reports_applied_config() {
  use_mock
  run_cli --iso "$ISO" --preset dev --name verifyvm
  assert_rc 0
  assert_contains "verify" "Verifying the VM configuration" "$ERR"
  assert_contains "verify" "memoria (MiB): 8192" "$ERR"
  assert_contains "verify" "controladora NVMe presente" "$ERR"
  assert_contains "verify" "SSH reenviado en el puerto 2222" "$ERR"
  assert_contains "verify" "Verificación correcta" "$ERR"
  assert_not_contains "verify" "se esperaba" "$ERR"
}

test_verify_detects_ignored_setting() {
  use_mock
  # A VirtualBox build that accepts --cpus but does not apply it.
  export MOCK_IGNORE="cpus=1"
  run_cli --iso "$ISO" --preset dev --name ignoredvm
  assert_rc 0
  assert_contains "verify" "se esperaba '4'" "$ERR"
  assert_contains "verify" "Verificación con avisos" "$ERR"
  assert_contains "verify" "--no-verify" "$ERR"
}

test_verify_detects_missing_tpm() {
  use_mock
  export MOCK_IGNORE="tpm-type=none"
  run_cli --iso "$WIN_ISO" --preset windows11 --name notpmvm
  assert_rc 0
  assert_contains "verify" "TPM" "$ERR"
  assert_contains "verify" "Verificación con avisos" "$ERR"
}

test_no_verify_flag() {
  use_mock
  run_cli --iso "$ISO" --preset dev --name noverifyvm --no-verify
  assert_rc 0
  assert_not_contains "verify" "Verifying the VM configuration" "$ERR"
  assert_not_contains "verify" "Verificación" "$ERR"
}

test_verify_skipped_in_dry_run() {
  use_mock
  run_cli --iso "$ISO" --preset dev --dry-run
  assert_rc 0
  assert_not_contains "verify" "Verifying" "$ERR"
  assert_no_log "showvminfo"
}

test_verify_checks_shared_folder_and_iso() {
  use_mock
  run_cli --iso "$ISO" --preset desktop --name shareverify \
    --shared-folder "code=$TEST_TMP/project"
  assert_rc 0
  assert_contains "verify" "ISO conectada" "$ERR"
  assert_contains "verify" "carpeta compartida 'code' registrada" "$ERR"
  assert_contains "verify" "Verificación correcta" "$ERR"
}

test_log_file() {
  use_mock
  local logf="$TEST_TMP/custom.log"
  run_cli --iso "$ISO" --name logvm --log-file "$logf"
  assert_rc 0
  assert_file "$logf"
  assert_contains "log" "RUN: " "$(cat "$logf")"
}

test_preset_list_is_readable() {
  hide_vbox
  run_cli --list-presets
  assert_rc 0
  assert_contains "specs" "NVMe" "$OUT"
  assert_contains "desc" "Daily development" "$OUT"
}

test_validate_presets() {
  hide_vbox
  OUT="$("$VALIDATOR" 2>&1 </dev/null)"
  RC=$?
  assert_rc 0
  assert_contains "validator" "0 error(s)" "$OUT"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
ALL_TESTS=(
  test_help_without_vbox
  test_version
  test_list_presets_without_vbox
  test_preset_list_is_readable
  test_unknown_option
  test_missing_iso_non_interactive
  test_unknown_preset
  test_invalid_ram
  test_invalid_vm_name
  test_size_units
  test_preset_values
  test_cli_overrides_preset
  test_clamp_resources
  test_force_resources
  test_relative_iso_becomes_absolute
  test_dry_run_without_vbox
  test_dry_run_without_iso
  test_dry_run_uses_valid_nvme_syntax
  test_full_create_dev
  test_no_nvme_uses_sata
  test_iso_none_skips_dvd
  test_headless_and_no_start
  test_windows11_requirements
  test_tpm_requires_vbox7
  test_secure_boot_fallback
  test_usb_falls_back_without_extpack
  test_usb_xhci_with_extpack
  test_ssh_port_collision
  test_extra_forward_from_preset
  test_cli_forward
  test_shared_folder
  test_shared_folder_readonly_and_tilde
  test_existing_vm_is_refused
  test_replace_requires_confirmation
  test_replace_with_yes
  test_bridged_autodetect
  test_network_alias_bridge
  test_invalid_network
  test_ostype_fallback
  test_partial_failure_gives_cleanup_hint
  test_existing_vm_has_no_cleanup_hint
  test_print_config_without_vbox_windows11
  test_verify_reports_applied_config
  test_verify_detects_ignored_setting
  test_verify_detects_missing_tpm
  test_no_verify_flag
  test_verify_skipped_in_dry_run
  test_verify_checks_shared_folder_and_iso
  test_log_file
  test_validate_presets
)

main() {
  local only=""
  while (( $# > 0 )); do
    case "$1" in
      -v|--verbose) VERBOSE=1; shift ;;
      -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
      *) only="$1"; shift ;;
    esac
  done

  printf '%bEasyVbox test suite%b (%s)\n\n' "$CYAN" "$NC" "$(basename "$SCRIPT")"

  local t
  for t in "${ALL_TESTS[@]}"; do
    if [[ -n "$only" && "$only" != "$t" ]]; then continue; fi
    run_test "$t"
  done

  local total=$(( PASS + FAIL ))
  printf '\n%d test(s): %b%d passed%b' "$total" "$GREEN" "$PASS" "$NC"
  if (( FAIL > 0 )); then
    printf ', %b%d failed%b\n' "$RED" "$FAIL" "$NC"
    printf 'Failed:\n'
    for t in "${FAILED_TESTS[@]}"; do printf '  - %s\n' "$t"; done
    exit 1
  fi
  printf '\n'
}

main "$@"
