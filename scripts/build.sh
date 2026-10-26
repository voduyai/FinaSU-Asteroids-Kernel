#!/usr/bin/env bash
# Build the Nothing Phone (3a) VoltageOS kernel with FinaSU built in.
#
# Same script for GitHub Actions and local builds (Linux / WSL). Options, as
# environment variables (1 = on, 0 = off):
#   FINASU_TAG    FinaSU release tag (empty = latest release)
#   SUSFS         SUSFS built into the kernel                  (default 1)
#   BBG           Baseband Guard                               (default 1)
#   NETWORKING    IP set, NAT/TTL, CAKE, BBR default, CIFS...  (default 1)
#   UNICODE_FIX   Unicode path bypass fix                      (default 1)
#   BBRV3         BBRv3 TCP congestion control                 (default 1)
#   WORK          work directory    (default ./work)
#   JOBS          make -j value     (default nproc)
# Each feature uses its upstream project's own setup script or patch.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../sources.env
. "$ROOT/sources.env"

FINASU_TAG=${FINASU_TAG:-}
SUSFS=${SUSFS:-1}
BBG=${BBG:-1}
NETWORKING=${NETWORKING:-1}
UNICODE_FIX=${UNICODE_FIX:-1}
BBRV3=${BBRV3:-1}
WORK=${WORK:-$ROOT/work}
JOBS=${JOBS:-$(nproc)}
OUT=$WORK/out
DIST=$WORK/dist
K=$WORK/common

export KBUILD_BUILD_USER=build-user KBUILD_BUILD_HOST=build-host
step() { printf '\n==== %s\n' "$*"; }
retry() { local n; for n in 1 2 3 4 5; do "$@" && return 0; echo "retry $n/5: $*" >&2; sleep $((n * 15)); done; return 1; }
github_api() { curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/$1"; }

mkdir -p "$WORK" "$DIST"
cd "$WORK"

step "Kernel source $KERNEL_SHA"
rm -rf "$K" && mkdir -p "$K"
git -C "$K" init -q
retry git -C "$K" fetch -q --depth=1 --no-tags "$KERNEL_REPO" "$KERNEL_SHA"
git -C "$K" checkout -q --detach FETCH_HEAD
[ "$(git -C "$K" rev-parse HEAD)" = "$KERNEL_SHA" ]
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) =' "$K/Makefile"

step "clang $CLANG_VERSION"
if [ ! -x "$WORK/clang/bin/clang" ]; then
    rm -rf "$WORK/clang" && mkdir -p "$WORK/clang"
    retry sh -c "curl -fsSL 'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-$CLANG_VERSION.tar.gz' | tar -xzf - -C '$WORK/clang'"
fi
export PATH="$WORK/clang/bin:$PATH"
clang --version | head -1

step "FinaSU"
if [ -z "$FINASU_TAG" ]; then
    FINASU_TAG=$(github_api "repos/$FINASU_REPO/releases/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
fi
rm -rf "$WORK/FinaSU"
# Full history: the kernel's version number is counted from the commits and
# the manager app checks it.
retry git clone -q "https://github.com/$FINASU_REPO.git" "$WORK/FinaSU"
git -C "$WORK/FinaSU" checkout -q "$FINASU_TAG"
echo "FinaSU $FINASU_TAG ($(git -C "$WORK/FinaSU" rev-parse --short HEAD)), $(git -C "$WORK/FinaSU" rev-list --count HEAD) commits"
# The kernel trusts only the manager certificate it is built with: take it
# from the release APK of the same tag.
rm -rf "$WORK/manager" && mkdir -p "$WORK/manager"
APK_URL=$(github_api "repos/$FINASU_REPO/releases/tags/$FINASU_TAG" |
    python3 -c 'import json,sys; print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".apk")))')
retry curl -fsSL -o "$WORK/manager/$(basename "$APK_URL")" "$APK_URL"
read -r CERT_SIZE CERT_HASH < <(python3 -I "$ROOT/scripts/apk_cert.py" "$WORK/manager/"*.apk)
echo "manager certificate: size $CERT_SIZE, sha256 $CERT_HASH"

if [ "$SUSFS" = 1 ]; then
    step "SUSFS (FinaSU docs/builtin-integration.md)"
    CHECK="$WORK/FinaSU/scripts/check-susfs-upstream.sh"
    [ -f "$CHECK" ] && grep -q '^config KSU_SUSFS$' "$WORK/FinaSU/kernel/Kconfig" ||
        { echo "FinaSU $FINASU_TAG has no built-in SUSFS support" >&2; exit 1; }
    PIN=$(sed -n 's/^EXPECTED_COMMIT=//p' "$CHECK")
    KMI=$(sed -n 's/^DEFAULT_KMI=//p' "$CHECK")
    [ "$KMI" = android15-6.6 ] || { echo "FinaSU checks SUSFS for $KMI, this kernel is android15-6.6" >&2; exit 1; }
    echo "susfs4ksu $PIN ($KMI), the commit FinaSU $FINASU_TAG is checked against"
    rm -rf "$WORK/susfs4ksu"
    retry git clone -q --filter=blob:none -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$WORK/susfs4ksu"
    git -C "$WORK/susfs4ksu" checkout -q "$PIN"
    FIFTY="$WORK/susfs4ksu/kernel_patches/50_add_susfs_in_gki-$KMI.patch"
    # FinaSU's own check, on the still-untouched kernel source.
    if ! sh "$CHECK" --upstream "$WORK/susfs4ksu" --kernel-source "$K" --kmi "$KMI" > "$WORK/susfs-check.log" 2>&1; then
        cat "$WORK/susfs-check.log"
        # Its 10-patch hunk list only reminds FinaSU's maintainers which
        # KernelSU-side hunks they ported (that patch is never applied), and
        # FinaSU v1.0.10 changed ksud_integration.c without refreshing it.
        # Accept that one failure only after every interface check passed, and
        # repeat the 50-patch dry run the script did not reach.
        grep -q '^Supercall commands: ' "$WORK/susfs-check.log" &&
            tail -n 1 "$WORK/susfs-check.log" | grep -q '10 patch failure fingerprint changed' ||
            { echo "FinaSU's SUSFS check failed" >&2; exit 1; }
        echo "::warning title=SUSFS check::FinaSU's 10-patch hunk list is out of date; interface checks passed"
        patch -d "$K" -p1 --dry-run --batch --forward < "$FIFTY" > "$WORK/fifty.log" || { cat "$WORK/fifty.log"; exit 1; }
        ! grep -Eq 'FAILED|Reversed \(or previously applied\)' "$WORK/fifty.log" || { cat "$WORK/fifty.log"; exit 1; }
        echo "50 patch dry run: clean"
    else
        cat "$WORK/susfs-check.log"
    fi
    # Kernel side only; never susfs4ksu's KernelSU patch (FinaSU carries that part).
    cp -r "$WORK/susfs4ksu/kernel_patches/fs" "$WORK/susfs4ksu/kernel_patches/include" "$K/"
    patch -d "$K" -p1 --forward --batch < "$FIFTY"
fi

step "FinaSU into the kernel (FinaSU kernel/setup.sh)"
(cd "$K" && sh "$WORK/FinaSU/kernel/setup.sh" --dir "$WORK/FinaSU")

if [ "$BBG" = 1 ]; then
    step "Baseband Guard $BBG_COMMIT (its setup.sh)"
    rm -rf "$K/Baseband-guard"
    retry git clone -q "$BBG_REPO" "$K/Baseband-guard"
    (cd "$K" && sh Baseband-guard/setup.sh "$BBG_COMMIT")
    [ "$(git -C "$K/Baseband-guard" rev-parse HEAD)" = "$BBG_COMMIT" ]
fi

if [ "$UNICODE_FIX" = 1 ] || [ "$BBRV3" = 1 ]; then
    step "kernel_patches $KERNEL_PATCHES_COMMIT"
    rm -rf "$WORK/kernel_patches"
    retry git clone -q --filter=blob:none "$KERNEL_PATCHES_REPO" "$WORK/kernel_patches"
    git -C "$WORK/kernel_patches" checkout -q "$KERNEL_PATCHES_COMMIT"
    if [ "$UNICODE_FIX" = 1 ]; then
        patch -d "$K" -p1 --forward --batch < "$WORK/kernel_patches/common/unicode_bypass_fix_6.1+.patch"
    fi
    if [ "$BBRV3" = 1 ]; then
        patch -d "$K" -p1 --forward --batch < "$WORK/kernel_patches/common/bbrv3/0001-net-tcp-backport-BBRv3-to-android15-6.6.patch"
    fi
fi

step "Match the stock kernel"
# system_dlkm modules are signed with the ROM's own key, which a rebuilt kernel
# does not have; an empty protected-exports list lets them load anyway.
rm -f "$K"/android/abi_gki_protected_exports_*
# Keep "-g<sha>" of the source commit although the tree is now modified.
SHORT=${KERNEL_SHA:0:12}
sed -i '$ s/\${scm_version}/-g'"$SHORT"'/' "$K/scripts/setlocalversion"
grep -q -- "-g$SHORT\"\$" "$K/scripts/setlocalversion" || { echo "could not pin the version string" >&2; exit 1; }

step "Configure"
MAKE=(make -C "$K" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1)
rm -rf "$OUT"
"${MAKE[@]}" gki_defconfig > /dev/null
(cd "$K" && ARCH=arm64 scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
    arch/arm64/configs/vendor/pineapple_perf.config arch/arm64/configs/vendor/asteroids_perf.config > /dev/null)
"${MAKE[@]}" olddefconfig > /dev/null
CFG() { "$K/scripts/config" --file "$OUT/.config" "$@"; }
# The stock kernel has no LTO; keep it so CFI matches the ROM's modules.
CFG -d LTO_CLANG_THIN -d LTO_CLANG_FULL -e LTO_NONE
# Must end up =y, or the build stops.
REQUIRED="KSU KPROBES EXT4_FS HEADERS_INSTALL"           # FinaSU builtin guide
[ "$SUSFS" = 1 ] && REQUIRED="$REQUIRED THREAD_INFO_IN_TASK KSU_SUSFS"
[ "$BBG" = 1 ] && REQUIRED="$REQUIRED BBG"
[ "$BBRV3" = 1 ] && REQUIRED="$REQUIRED TCP_CONG_BBR3"
for opt in $REQUIRED; do CFG -e "$opt"; done
if [ "$BBG" = 1 ]; then
    # Baseband Guard's instructions: append it to the LSM order.
    LSM=$(sed -n 's/^CONFIG_LSM="\(.*\)"/\1/p' "$OUT/.config")
    case ",$LSM," in *,baseband_guard,*) ;; *) CFG --set-str LSM "$LSM,baseband_guard" ;; esac
fi
if [ "$NETWORKING" = 1 ]; then
    # WildKernel's networking set (IP set, firewall matches, NAT/TTL,
    # congestion control with BBR default, qdiscs, WireGuard, CIFS).
    while read -r opt val; do
        case "$val" in
        y) CFG -e "$opt" ;;
        \"*) CFG --set-str "$opt" "${val//\"/}" ;;
        *) CFG --set-val "$opt" "$val" ;;
        esac
    done < "$ROOT/networking.config.list"
fi
"${MAKE[@]}" olddefconfig > /dev/null
for opt in $REQUIRED; do
    grep -q "^CONFIG_$opt=y" "$OUT/.config" || { echo "CONFIG_$opt is not y" >&2; exit 1; }
done
if [ "$NETWORKING" = 1 ]; then
    missing=$(while read -r opt val; do grep -qx "CONFIG_$opt=$val" "$OUT/.config" || echo "$opt"; done < "$ROOT/networking.config.list")
    [ -z "$missing" ] || echo "::warning title=networking::not applied (unmet dependencies): $(echo $missing)"
fi
grep -E '^CONFIG_(LTO_NONE|KSU|HEADERS_INSTALL|BBG|LSM|TCP_CONG_BBR3|DEFAULT_TCP_CONG)' "$OUT/.config"

step "Build"
# Release key in the second manager slot, as FinaSU's release builds do.
# KSU_REQUIRE_PREINIT=1: fail instead of silently dropping preinit.
"${MAKE[@]}" -j"$JOBS" \
    KSU_EXPECTED_SIZE2="$CERT_SIZE" KSU_EXPECTED_HASH2="$CERT_HASH" \
    KSU_SECOND_SIGNATURE_RELEASE=1 KSU_REQUIRE_PREINIT=1 Image

step "Result"
IMAGE="$OUT/arch/arm64/boot/Image"
grep -a -o -m1 'Linux version [^(]*([^)]*)' "$IMAGE"
grep -q "$CERT_HASH" "$IMAGE" || { echo "manager certificate not embedded" >&2; exit 1; }
FEATURES="FinaSU-$FINASU_TAG"
[ "$SUSFS" = 1 ] && FEATURES="$FEATURES-SUSFS"
[ "$BBG" = 1 ] && FEATURES="$FEATURES-BBG"
[ "$NETWORKING" = 1 ] && FEATURES="$FEATURES-NET"
[ "$UNICODE_FIX" = 1 ] && FEATURES="$FEATURES-Unicode"
[ "$BBRV3" = 1 ] && FEATURES="$FEATURES-BBRv3"
NAME="$FEATURES-asteroids-6.6.144"
rm -rf "$DIST" "$WORK/ak3" && mkdir -p "$DIST"
retry git clone -q --depth=1 https://github.com/osm0sis/AnyKernel3.git "$WORK/ak3"
rm -rf "$WORK/ak3/.git" "$WORK/ak3/.github" "$WORK/ak3/README.md" "$WORK/ak3/modules" "$WORK/ak3/patch" "$WORK/ak3/ramdisk"
cp "$ROOT/anykernel.sh" "$IMAGE" "$WORK/ak3/"
(cd "$WORK/ak3" && zip -qr9 "$DIST/$NAME-AnyKernel3.zip" .)
cp "$IMAGE" "$OUT/.config" "$WORK/manager/"*.apk "$DIST/"
echo "$NAME" > "$DIST/NAME"
ls -la "$DIST"
