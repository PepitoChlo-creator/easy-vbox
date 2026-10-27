#!/usr/bin/env bash
# Validate isos/catalog.tsv.
#
#   ./scripts/validate-catalog.sh
#
# Checks the format of every entry (fields, URLs, name rules, resolvability)
# so a broken catalog line is caught in CI instead of during a 5 GB download.
# It does not hit the network: what it checks is the catalog itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="${EASYVBOX_ISO_CATALOG:-$ROOT_DIR/isos/catalog.tsv}"

RED=''; GREEN=''; YELLOW=''; NC=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
fi

ERRORS=0
WARNINGS=0
CHECKED=0
before=0

err()  { printf '%b✗%b %s\n' "$RED" "$NC" "$*"; ERRORS=$(( ERRORS + 1 )); }
warn() { printf '%b⚠%b %s\n' "$YELLOW" "$NC" "$*"; WARNINGS=$(( WARNINGS + 1 )); }

if [[ ! -r "$CATALOG" ]]; then
  printf '%b✗%b catalog not found: %s\n' "$RED" "$NC" "$CATALOG"
  exit 1
fi

SEEN_NAMES=""

while IFS= read -r line; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  CHECKED=$(( CHECKED + 1 ))
  before="$ERRORS"

  # name | family | size_gb | checksums_url | file_pattern | direct_url | checksum_url | notes
  name="$(printf '%s' "$line" | awk -F'|' '{print $1}')"
  family="$(printf '%s' "$line" | awk -F'|' '{print $2}')"
  size="$(printf '%s' "$line" | awk -F'|' '{print $3}')"
  sums_url="$(printf '%s' "$line" | awk -F'|' '{print $4}')"
  pattern="$(printf '%s' "$line" | awk -F'|' '{print $5}')"
  direct_url="$(printf '%s' "$line" | awk -F'|' '{print $6}')"
  checksum_url="$(printf '%s' "$line" | awk -F'|' '{print $7}')"
  notes="$(printf '%s' "$line" | awk -F'|' '{print $8}')"

  fields="$(printf '%s' "$line" | awk -F'|' '{print NF}')"
  [[ "$fields" == "8" ]] || err "'${name:-<no name>}': expected 8 fields, found $fields"

  if [[ -z "$name" ]]; then
    err "entry without a name: $line"
    continue
  fi
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] \
    || err "'$name': invalid name (lowercase letters, digits, dot, dash, underscore)"
  case " $SEEN_NAMES " in
    *" $name "*) err "'$name': duplicated entry" ;;
  esac
  SEEN_NAMES="$SEEN_NAMES $name"

  [[ -n "$family" ]] || err "'$name': missing family"
  [[ -z "$size" || "$size" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || err "'$name': size_gb must be a number (got '$size')"
  [[ -n "$notes" ]] || warn "'$name': no description"

  # Resolvability: a checksum list plus pattern, or a direct URL.
  if [[ -n "$pattern" && -n "$sums_url" ]]; then
    [[ "$sums_url" == https://* ]] || err "'$name': checksums_url must be https"
  elif [[ -n "$direct_url" ]]; then
    [[ "$direct_url" == https://* ]] || err "'$name': direct_url must be https"
    [[ "$direct_url" == *.iso ]] || warn "'$name': direct_url does not end in .iso"
    [[ -z "$checksum_url" || "$checksum_url" == https://* ]] \
      || err "'$name': checksum_url must be https"
  else
    err "'$name': needs either checksums_url + file_pattern, or direct_url"
  fi

  if (( ERRORS == before )); then
    printf '%b✓%b %s\n' "$GREEN" "$NC" "$name"
  else
    printf '%b✗%b %s (see errors above)\n' "$RED" "$NC" "$name"
  fi
done <"$CATALOG"

if (( CHECKED == 0 )); then
  err "the catalog is empty"
fi

printf '\n%d entr(ies) checked — %d error(s), %d warning(s)\n' "$CHECKED" "$ERRORS" "$WARNINGS"
(( ERRORS == 0 )) || exit 1
