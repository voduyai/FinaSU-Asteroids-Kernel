# FinaSU kernel for Nothing Phone (3a) – VoltageOS

Rebuilds the exact kernel VoltageOS ships, `6.6.144-android15-8-4k-g580b8ea6c4fb`, with [FinaSU](https://github.com/LyraVoid/FinaSU) built in, plus optional SUSFS, Baseband Guard, networking extras and the Unicode fix.

Every feature is added the way its own project documents it. Nothing is merged or patched by hand.

## Features

| Feature | Default | How it is added |
|---|---|---|
| FinaSU (latest release) | always | FinaSU's `kernel/setup.sh --dir`, options and make flags from its `docs/builtin-integration.md` (`KSU`, `KPROBES`, `EXT4_FS`, `HEADERS_INSTALL`, `KSU_REQUIRE_PREINIT=1`). Includes network isolation and hide mount records |
| SUSFS built in | on | The `susfs4ksu` commit FinaSU pins (`EXPECTED_COMMIT` in its `scripts/check-susfs-upstream.sh`), checked with that script first. Only the kernel-side patch is applied; FinaSU carries the KernelSU side |
| Baseband Guard | on | `vc-teahouse/Baseband-guard`'s `setup.sh` at a pinned commit, `CONFIG_BBG=y`, `baseband_guard` appended to `CONFIG_LSM` as its instructions say |
| Networking | on | WildKernel's networking set (`networking.config.list`): IP set, firewall matches, IPv6 NAT, TTL/HL, BBR as default, CAKE/FQ, CONNMARK, WireGuard, CIFS |
| Unicode fix | on | `unicode_bypass_fix_6.1+.patch` from `WildKernels/kernel_patches` |
| BBRv3 | off | `0001-net-tcp-backport-BBRv3-to-android15-6.6.patch` from `WildKernels/kernel_patches`. Changes TCP internals; test separately |
| BPF / BTF / eBPF / FUSE-BPF | always | Already enabled in the stock VoltageOS kernel |

## Matching the stock kernel

| Item | Value |
|---|---|
| Source | `pixelos-asteroids/android_kernel_nothing_sm7635` @ `580b8ea6c4fb` |
| Config | `gki_defconfig` + `vendor/pineapple_perf.config` + `vendor/asteroids_perf.config`, LTO off |
| Compiler | clang `r596125` (22.0.2), the ROM's own. Any other clang changes the CRCs of `icc_*` symbols and the phone hangs on the logo |
| Version | `-g580b8ea6c4fb` kept |
| Protected exports | Emptied, so `system_dlkm` modules (signed with the ROM's key) still load |
| Manager signature | Certificate of the same release's APK (`scripts/apk_cert.py`), in the second slot with `KSU_SECOND_SIGNATURE_RELEASE=1`, as FinaSU's release builds do |

All pins live in `sources.env`.

## Build

**Actions → Build kernel → Run workflow.** Leave the fields as they are for the full build. It takes about 25 minutes.

Or locally on Linux / WSL (needs `bc bison flex cpio libssl-dev libelf-dev dwarves zip git curl python3`):

```bash
bash scripts/build.sh
```

Turn features off with environment variables, e.g. `SUSFS=0 BBRV3=1 bash scripts/build.sh`.

The artifact contains:
- `Image`: the kernel
- `*-AnyKernel3.zip`: flashable zip
- `FinaSU_*.apk`: the manager app matching the kernel
- `.config`: the real kernel config

## Install

1. Use the **stock** `init_boot` (not one patched with KernelSU LKM). Remove any SUSFS LKM module if one is installed.
2. Put `Image` into the stock VoltageOS `boot.img`:
   ```bash
   magiskboot unpack boot.img
   cp Image kernel
   magiskboot repack boot.img new-boot.img
   ```
3. Boot-test first, don't flash yet:
   ```bash
   fastboot boot new-boot.img
   ```
4. Install the FinaSU APK from the artifact. Flash only after root, modules and SUSFS work.

## When VoltageOS updates

The kernel only fits the ROM build it was made for. If `uname -r` changes after an update, find the new commit in the ROM's kernel tree, set `KERNEL_SHA` in `sources.env`, check which clang the ROM uses, and rebuild.
