## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] `make test` passes locally (syntax, ShellCheck if installed, presets, catalog, suite)
- [ ] New behaviour has a test in `tests/run-tests.sh` (or a reason it cannot)
- [ ] Works on macOS with bash 3.2 — no `mapfile`, no `declare -A`, no `${var,,}`
- [ ] No new runtime dependency (jq, python, yq… are deliberately avoided)
- [ ] Docs updated: `README.md` cheat sheet and `docs/ADVANCED.md` / `docs/PRESETS.md`
- [ ] `CHANGELOG.md` has an entry under the next version

## If this adds or changes a preset

- [ ] Values are real and differ from the closest existing preset
- [ ] Documented in **both** `README.md` and `docs/PRESETS.md`
- [ ] `./scripts/validate-presets.sh` is clean

## If this changes what a release ships

- [ ] `scripts/release-payload.sh` covers the new paths
      (a previous release silently shipped without `isos/` and broke `--download`)

## Verification

<!-- Paste the relevant output: test summary, validate-presets, dry-run plan. -->

```text
$ ./tests/run-tests.sh
```

## Notes for the reviewer

<!-- Anything risky, anything you were unsure about, anything deliberately left out. -->
