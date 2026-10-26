# FinaSU kernel for Nothing Phone (3a) – VoltageOS

Rebuilds the exact kernel VoltageOS ships, `6.6.144-android15-8-4k-g580b8ea6c4fb`, with [FinaSU](https://github.com/LyraVoid/FinaSU) built in, plus optional SUSFS, Baseband Guard, networking extras and the Unicode fix.

Every feature is added the way its own project documents it. Nothing is merged or patched by hand.

## Features

| Feature | Default | How it is added |
|---|---|---|
| [FinaSU](https://github.com/LyraVoid/FinaSU/releases) (latest release) | always | FinaSU's [`kernel/setup.sh`](https://github.com/LyraVoid/FinaSU/blob/master/kernel/setup.sh) `--dir`, options and make flags from its [`docs/builtin-integration.md`](https://github.com/LyraVoid/FinaSU/blob/master/docs/builtin-integration.md) (`KSU`, `KPROBES`, `EXT4_FS`, `HEADERS_INSTALL`, `KSU_REQUIRE_PREINIT=1`). Includes network isolation and hide mount records |
| SUSFS built in | on | The [`susfs4ksu`](https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android15-6.6) commit FinaSU pins (`EXPECTED_COMMIT` in its [`scripts/check-susfs-upstream.sh`](https://github.com/LyraVoid/FinaSU/blob/master/scripts/check-susfs-upstream.sh)), checked with that script first. Only the kernel-side patch is applied; FinaSU carries the KernelSU side |
| Baseband Guard | on | [`vc-teahouse/Baseband-guard`](https://github.com/vc-teahouse/Baseband-guard)'s `setup.sh` at a pinned commit, `CONFIG_BBG=y`, `baseband_guard` appended to `CONFIG_LSM` as its instructions say |
| Networking | on | [WildKernel's networking set](https://github.com/WildKernels/GKI_KernelSU_SUSFS/blob/main/.github/actions/networking-config/action.yml) (`networking.config.list`): IP set, firewall matches, IPv6 NAT, TTL/HL, BBR as default, CAKE/FQ, CONNMARK, WireGuard, CIFS |
| Unicode fix | on | [`unicode_bypass_fix_6.1+.patch`](https://github.com/WildKernels/kernel_patches/blob/159a8f3b93af582b07d0d44bfa7d08b96d667ec0/common/unicode_bypass_fix_6.1%2B.patch) from `WildKernels/kernel_patches` |
| BBRv3 | on | [`0001-net-tcp-backport-BBRv3-to-android15-6.6.patch`](https://github.com/WildKernels/kernel_patches/blob/159a8f3b93af582b07d0d44bfa7d08b96d667ec0/common/bbrv3/0001-net-tcp-backport-BBRv3-to-android15-6.6.patch) from `WildKernels/kernel_patches`. Changes TCP internals. Boots on this phone (tested 2026-10-26 with every other feature on). Still `bbr` (v1) by default; switch with `echo bbr3 > /proc/sys/net/ipv4/tcp_congestion_control` |
| BPF / BTF / eBPF / FUSE-BPF | always | Already enabled in the stock VoltageOS kernel |

## Matching the stock kernel

| Item | Value |
|---|---|
| Source | [`pixelos-asteroids/android_kernel_nothing_sm7635` @ `580b8ea6c4fb`](https://github.com/pixelos-asteroids/android_kernel_nothing_sm7635/commit/580b8ea6c4fbcd96425476f5f63c17cac6b824e4) |
| Config | `gki_defconfig` + `vendor/pineapple_perf.config` + `vendor/asteroids_perf.config`, LTO off |
| Compiler | clang `r596125` (22.0.2) from [Android's clang prebuilts](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/mirror-goog-main-llvm-toolchain-source), the ROM's own. Any other clang changes the CRCs of `icc_*` symbols and the phone hangs on the logo |
| Version | `-g580b8ea6c4fb` kept |
| Protected exports | Emptied, so `system_dlkm` modules (signed with the ROM's key) still load |
| Manager signature | Certificate of the same release's APK (`scripts/apk_cert.py`), in the second slot with `KSU_SECOND_SIGNATURE_RELEASE=1`, as FinaSU's release builds do |

All pins live in `sources.env`.

## Build

**Actions → Build kernel → Run workflow.** Leave the fields as they are for the full build. It takes about 25 minutes.

Or on your own Linux / WSL machine, usually faster. See **[docs/building-locally.md](docs/building-locally.md)** for the full guide (WSL setup, options, troubleshooting):

```bash
sudo bash scripts/install-deps.sh
bash scripts/build.sh
```

Turn features off with environment variables, e.g. `SUSFS=0 BBRV3=0 bash scripts/build.sh`.

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

If the phone hangs on the logo after installing a KernelSU module, it is usually the module, not the kernel. Boot into safe mode (press volume down repeatedly while booting) to start with all modules off, then remove the module in the app.

## When VoltageOS updates

The kernel only fits the ROM build it was made for. If `uname -r` changes after an update, find the new commit in the ROM's kernel tree, set `KERNEL_SHA` in `sources.env`, check which clang the ROM uses, and rebuild.

## Sources and credits

| Project | Used for |
|---|---|
| [LyraVoid/FinaSU](https://github.com/LyraVoid/FinaSU) | Root (KernelSU fork), manager app, built-in SUSFS support, NoMount. Guide: [builtin-integration.md](https://github.com/LyraVoid/FinaSU/blob/master/docs/builtin-integration.md) |
| [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android15-6.6) | SUSFS kernel patch, branch `gki-android15-6.6` |
| [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) | Baseband Guard LSM ([pinned commit](https://github.com/vc-teahouse/Baseband-guard/commit/a54e0dc6cf0aff4dd87fec49644a02d2eb612905)) |
| [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches/tree/159a8f3b93af582b07d0d44bfa7d08b96d667ec0) | Unicode fix and BBRv3 patches |
| [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS) | Networking config set |
| [pixelos-asteroids/android_kernel_nothing_sm7635](https://github.com/pixelos-asteroids/android_kernel_nothing_sm7635) | Kernel source matching the VoltageOS build |
| [voltageos-asteroids/device_nothing_asteroids](https://github.com/voltageos-asteroids/device_nothing_asteroids) | How VoltageOS configures and builds its kernel |
| [voltageos-asteroids/kernel_nothing_sm7635](https://github.com/voltageos-asteroids/kernel_nothing_sm7635) | VoltageOS's own kernel tree (for comparison) |
| [Android clang prebuilts](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/mirror-goog-main-llvm-toolchain-source) | clang `r596125` |
| [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) | Flashable zip |
| [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk) | `magiskboot`, for repacking `boot.img` |
| [Microsoft WSL docs](https://learn.microsoft.com/windows/wsl/install) | Setting up WSL for local builds ([`.wslconfig`](https://learn.microsoft.com/windows/wsl/wsl-config)) |
