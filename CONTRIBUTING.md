# Contributing

Thanks for helping. The most valuable contributions are **presets that solve a
real problem** and **bug reports with a log**.

## Before you start

```bash
git clone https://github.com/PepitoChlo-creator/easy-vbox.git
cd easy-vbox
./scripts/install.sh --no-tools
make test
```

`make test` runs syntax checks, ShellCheck (if installed), preset validation
and the test suite. Everything must be green before opening a pull request.

## Adding a preset

1. Copy a preset that is close to what you need, e.g. `presets/dev.json`.
2. Give it a `name` matching the file name and **real** values — the whole point
   is that presets differ. Avoid copies with a new filename.
3. Validate:

   ```bash
   ./scripts/validate-presets.sh your-preset
   ```

   It checks the schema, ranges, enums, port-forward syntax and whether the
   preset is documented.

4. Document it in **both** places:
   - the table in `README.md`
   - the table in `docs/PRESETS.md` (with a one-line rationale)

5. Add nothing to the test suite unless the preset needs special handling —
   `test_validate_presets` validates every preset automatically.

### Preset rules

- Flat JSON only (no nested objects, no arrays). `port_forwards` and `tags` are
  comma-separated strings on purpose: the runtime parser is dependency-free.
- Use `schema: 2`. Unknown keys are errors, which is how typos get caught.
- Values must be sane defaults: `ram_mb` ≥ 256, `cpus` ≥ 1, `disk_mb` ≥ 4096.
- `secure_boot: "on"` requires `firmware: "efi"` and `tpm: "2.0"`.
- Do not put absolute host paths in `shared_folder`; that is for users.

## Adding an ISO catalog entry

`isos/catalog.tsv` maps a friendly name to an official download. Prefer the
checksum-list mode (a `SHA256SUMS` URL plus a wildcard pattern) so point
releases keep working, and run:

```bash
./scripts/validate-catalog.sh
```

Do not hard-code Windows evaluation links: they expire. Details in
[`docs/ISOS.md`](docs/ISOS.md).

## Working on the scripts

- Bash 3.2 compatibility is required (macOS ships bash 3.2). No associative
  arrays, no `${var,,}`, no `mapfile`, no `readarray`.
- No runtime dependencies. `jq`/`python3` may only be used in
  `scripts/validate-presets.sh`, and it must degrade gracefully.
- Keep `scripts/create-vm.sh` a single file; it is meant to be copy-pasted
  standalone.
- `shellcheck -S style` must be clean:

  ```bash
  make lint
  ```

- New behaviour needs a test in `tests/run-tests.sh`. Use the fake `VBoxManage`
  in `tests/mock/` — tests must never require a real hypervisor.
- The mock stores settings and renders them through `showvminfo`, so tests can
  assert the resulting configuration and not only the command sequence. Use
  `MOCK_IGNORE="key=value"` to simulate a build that silently ignores a
  setting.
- Network code must go through `EASYVBOX_DOWNLOADER`. Tests use
  `tests/mock/fake-downloader` with a URL-to-file mapping, so the suite never
  touches the network.
- Write user-facing messages to **stderr** and machine-readable output
  (`--print-config`, dry-run plan, listings) to **stdout**.

### Running a single test

```bash
./tests/run-tests.sh test_full_create_dev
./tests/run-tests.sh -v          # show every VBoxManage call
```

## Reporting a bug

Include:

```bash
VBoxManage --version
uname -a
./scripts/create-vm.sh --iso image.iso --preset dev --print-config
tail -40 ~/.easyvbox/logs/create-vm-*.log
```

The log contains the exact command that failed and VirtualBox's error message;
without it, most issues cannot be reproduced.

## Pull requests

- One topic per PR. Preset additions can be one PR with several presets if they
  belong to the same theme.
- Keep the commit history readable; a descriptive title is enough.
- Update `CHANGELOG.md` when behaviour changes.

## Code of conduct

Be decent. Assume good faith, criticise code rather than people, and keep the
discussion useful for whoever reads it later.
