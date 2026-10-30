#!/usr/bin/env bash
# EasyVbox — the files that ship inside a release tarball.
#
# Prints one path per line, relative to the repository root. This is the single
# source of truth for the release payload: .github/workflows/release.yml builds
# the tarball from this list and tests/run-tests.sh checks that every entry
# exists. Adding a directory the scripts read at runtime (like isos/) only needs
# to happen here.
#
# Kept in bash 3.2 so it runs on macOS too (no mapfile, no associative arrays).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

payload=(
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  LICENSE
  Makefile
  docs
  presets
  scripts
  tests
  isos          # ISO catalog: required by --download and --list-isos
  .gitignore    # so the tarball behaves like a checkout
)

missing=0
for path in "${payload[@]}"; do
  if [[ ! -e "$path" ]]; then
    printf 'release payload: missing %s\n' "$path" >&2
    missing=1
    continue
  fi
  printf '%s\n' "$path"
done

exit "$missing"
