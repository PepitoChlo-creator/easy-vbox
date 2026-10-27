# Presets

A preset is a flat JSON file in `presets/` that describes a VM for one use case.
EasyVbox ships 12 of them; `--preset NAME` loads one and the command line can
override any value.

```bash
./scripts/create-vm.sh --iso ubuntu.iso --preset dev
./scripts/create-vm.sh --iso ubuntu.iso --preset dev --ram 4G --no-3d
```

## The 12 presets

| Preset | RAM | CPUs | Disk | NVMe | 3D | USB | Other |
|---|---:|:---:|---:|:---:|:---:|:---:|---|
| `basic` | 2048 | 2 | 25600 | yes | no | ohci | Throwaway tests and one-off commands |
| `dev` | 8192 | 4 | 61440 | yes | yes | xhci | Nested virt, the recommended default |
| `fullstack` | 12288 | 6 | 102400 | yes | no | ohci | Nested virt, publishes 8080/8443 |
| `server` | 4096 | 2 | 51200 | yes | no | ohci | Headless, 16 MiB VRAM |
| `desktop` | 6144 | 4 | 81920 | yes | yes | xhci | Everyday desktop |
| `gaming` | 16384 | 8 | 122880 | yes | yes | xhci | 256 MiB VRAM, VBoxSVGA |
| `windows11` | 8192 | 4 | 131072 | yes | yes | xhci | UEFI + TPM 2.0 + Secure Boot |
| `kali` | 6144 | 4 | 81920 | yes | yes | xhci | Nested virt for in-guest VMs |
| `ctf` | 4096 | 2 | 40960 | yes | no | ohci | Fast boot, small disk |
| `android-dev` | 8192 | 4 | 102400 | yes | yes | xhci | Nested virt, forwards 5555 |
| `data-science` | 16384 | 8 | 153600 | yes | no | ohci | Jupyter on 8888 |
| `minimal-testing` | 1024 | 1 | 10240 | no | no | ohci | Headless, SATA only, CI |

Sizes are MiB. RAM and CPU values are clamped down to what your host can
safely give (see `--force-resources`).

## Schema (version 2)

Every preset is a single flat JSON object. Keys must be from this list —
unknown keys are validation errors, so a typo never silently does nothing.

| Key | Type | Required | Meaning |
|---|---|:---:|---|
| `schema` | integer | yes | Must be `2` |
| `name` | string | yes | Must match the file name (`dev.json` → `"dev"`) |
| `description` | string | yes | One line shown by `--list-presets` |
| `ram_mb` | integer | yes | Memory in MiB (256 – 1048576) |
| `cpus` | integer | yes | Virtual CPUs (1 – 128) |
| `disk_mb` | integer | yes | Disk size in MiB (4096 – 16777216) |
| `nvme` | boolean | yes | NVMe on PCIe instead of SATA |
| `accelerate_3d` | boolean | yes | Hardware 3D acceleration |
| `vram_mb` | integer | no | Video memory, 4 – 256 |
| `graphics_controller` | string | no | `vmsvga`, `vboxsvga` or `none` |
| `firmware` | string | no | `efi` or `bios` |
| `tpm` | string | no | `none` or `2.0` (needs VirtualBox 7+) |
| `secure_boot` | string | no | `on` or `off` (needs EFI + VirtualBox 7+) |
| `nested_virt` | boolean | no | Expose VT-x/AMD-V to the guest |
| `usb` | string | no | `off`, `ohci`, `ehci` or `xhci` |
| `headless` | boolean | no | Start without a window |
| `shared_folder` | string/null | no | Absolute host path or `null` |
| `port_forwards` | string | no | `NAME:HOST:GUEST`, comma separated |
| `tags` | string | no | Comma-separated labels for humans |

The defaults used when a key is missing: `vram_mb` 128, `graphics_controller`
`vmsvga`, `firmware` `efi`, `tpm` `none`, `secure_boot` `off`, `nested_virt`
false, `usb` `ohci`, `headless` false, shared folder none, no extra forwards.

Host ports must be free on your machine; EasyVbox only checks conflicts with
other VirtualBox VMs, not with arbitrary host processes.

## Adding a preset

1. Copy an existing file, for example `presets/dev.json`.
2. Change `name` (must equal the file name) and the values.
3. Validate it:

   ```bash
   ./scripts/validate-presets.sh your-preset
   ```

4. Document it: add a row to the table above **and** mention it in
   `README.md`. The validator fails if a preset is missing from the docs.
5. Run the test suite (it validates every preset):

   ```bash
   ./tests/run-tests.sh
   ```

### Example: a Kubernetes lab

```json
{
  "schema": 2,
  "name": "k8s-lab",
  "description": "Single-node Kubernetes lab with nested virtualization",
  "ram_mb": 16384,
  "cpus": 6,
  "disk_mb": 122880,
  "nvme": true,
  "accelerate_3d": false,
  "vram_mb": 32,
  "graphics_controller": "vmsvga",
  "firmware": "efi",
  "tpm": "none",
  "secure_boot": "off",
  "nested_virt": true,
  "usb": "ohci",
  "headless": false,
  "shared_folder": null,
  "port_forwards": "api:6443:6443,ingress:8080:80",
  "tags": "kubernetes,lab"
}
```

```bash
./scripts/create-vm.sh --iso ubuntu-24.04.iso --preset k8s-lab
kubectl --server=https://localhost:6443 ...
```

## Presets and overrides

Presets are a starting point, not a cage. Every field has a matching flag and
**command-line flags always win**, including booleans:

```bash
--ram 16G --cpus 8 --disk 120G --vram 256
--nvme / --no-nvme
--3d / --no-3d
--nested / --no-nested
--usb xhci --tpm 2.0 --secure-boot on
--graphics vboxsvga --firmware efi
--headless / --gui / --no-start
```

To see the final result of preset + flags without touching anything:

```bash
./scripts/create-vm.sh --iso ubuntu.iso --preset gaming --ram 8G --print-config
```
