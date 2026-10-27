# ISO downloads

`--download` removes the "open a browser, find the right file, copy the path"
step. EasyVbox resolves the image, downloads it once into a cache and reuses it
afterwards.

```bash
./scripts/create-vm.sh --list-isos
./scripts/create-vm.sh --download ubuntu-24.04-server --preset server
./scripts/create-vm.sh --download https://example.org/custom.iso --name custom
```

## How it resolves an image

The catalog lives in `isos/catalog.tsv`, one entry per line:

```text
name | family | size_gb | checksums_url | file_pattern | direct_url | checksum_url | notes
```

There are two resolution modes:

**1. Checksum list (preferred).** `checksums_url` points at an upstream
`SHA256SUMS`-style file and `file_pattern` selects the image. EasyVbox reads the
list, takes the file name *and* the SHA-256 from it, and downloads from the same
directory. This is what keeps entries working across point releases: the
catalog says `*amd64-netinst.iso`, not `debian-12.9.0-amd64-netinst.iso`.

**2. Direct URL.** `direct_url` is downloaded as-is, optionally verified against
`checksum_url` (a file whose first field is the hex digest). Used for projects
that publish a stable file name, such as openSUSE's `-Current.iso`.

## Cache

- Location: `~/.easyvbox/isos` (override with `--iso-cache DIR` or
  `EASYVBOX_ISO_CACHE`).
- If the file is already there and its checksum matches, nothing is downloaded.
  EasyVbox says so and moves on.
- A cached file whose checksum does **not** match is downloaded again.
- Partial downloads resume (`curl -C -`, `wget -c`).
- A file that fails verification after downloading is deleted, so a corrupt
  image never reaches a VM.

## Verification

SHA-256 is checked with `sha256sum`, `shasum -a 256` or `openssl dgst -sha256`,
whichever exists. If none is available, EasyVbox warns instead of pretending to
have verified anything.

```text
▶ Downloading debian-12.9.0-amd64-netinst.iso
   from https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso
   to   /home/you/.easyvbox/isos/debian-12.9.0-amd64-netinst.iso
✓ Checksum verified
✓ Downloaded debian-12.9.0-amd64-netinst.iso
```

## The catalog

| Name | Family | Approx. size | What it is |
|---|---|---:|---|
| `ubuntu-24.04-desktop` | ubuntu | 5.7 GB | Ubuntu 24.04 LTS Desktop |
| `ubuntu-24.04-server` | ubuntu | 3.0 GB | Ubuntu 24.04 LTS Server, no desktop |
| `ubuntu-22.04-server` | ubuntu | 1.9 GB | Ubuntu 22.04 LTS Server |
| `debian-12-netinst` | debian | 0.7 GB | Debian 12 netinst, installs from the network |
| `debian-12-dvd` | debian | 4.0 GB | Debian 12 DVD 1, offline install |
| `arch-latest` | arch | 1.2 GB | Arch Linux, current monthly image |
| `kali-latest` | kali | 5.0 GB | Kali installer, current release |
| `rocky-9-minimal` | rhel | 2.0 GB | Rocky Linux 9 minimal |
| `opensuse-tumbleweed-net` | suse | 0.5 GB | openSUSE Tumbleweed network installer |
| `alpine-virt` | alpine | 0.1 GB | Alpine virtual image, tiny and fast |

Windows evaluation images are deliberately **not** in the catalog: Microsoft
generates the download link per request and it expires, so a pinned entry would
rot. Download the ISO yourself and pass `--iso`.

## Adding or fixing an entry

```bash
# One line, eight pipe-separated fields
my-distro|debian|1.2|https://example.org/iso/SHA256SUMS|*amd64-netinst.iso|||My distro, short note

./scripts/validate-catalog.sh
```

The validator checks the field count, the name rules, `https` on every URL, that
the entry is resolvable (checksum list + pattern, or a direct URL) and that
names are unique. It does **not** hit the network — that would make CI flaky and
slow — so a moved upstream file is only noticed when someone runs the download.

If an entry stops working, the fix is one line: adjust the pattern or the URL.
The download error names the URL and the pattern it looked for.

## Environment variables

| Variable | Effect |
|---|---|
| `EASYVBOX_ISO_CACHE` | Cache directory, same as `--iso-cache` |
| `EASYVBOX_ISO_CATALOG` | Use a different catalog file |
| `EASYVBOX_DOWNLOADER` | Replace curl/wget (the test suite uses this) |

## Why not just `curl` in a `for` loop?

Because the failure modes are the interesting part: a point release that
renames the file, a truncated download, a mirror serving the wrong bytes, a
re-download of 5 GB that is already on disk. The catalog plus checksum
verification handles all four, and the test suite covers them offline with a
fake downloader.
