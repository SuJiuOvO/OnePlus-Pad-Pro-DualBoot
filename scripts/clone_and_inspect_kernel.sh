#!/bin/bash
set -euo pipefail

BUILD_ROOT="/var/cache/caihong_kernel_build"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

if [ ! -d "$BUILD_ROOT/linux/.git" ]; then
    echo "Cloning Osilvfe/linux (branch caihong-v7.3, depth=1)..."
    git clone --depth=1 --branch caihong-v7.3 https://github.com/Osilvfe/linux.git "$BUILD_ROOT/linux"
else
    echo "linux repo already exists at $BUILD_ROOT/linux"
fi

if [ ! -d "$BUILD_ROOT/mkbootimg/.git" ]; then
    echo "Cloning mkbootimg..."
    git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg "$BUILD_ROOT/mkbootimg"
else
    echo "mkbootimg repo already exists at $BUILD_ROOT/mkbootimg"
fi

echo "=== linux git HEAD ==="
git -C "$BUILD_ROOT/linux" log -1 --oneline
echo "=== linux Makefile VERSION ==="
head -n 6 "$BUILD_ROOT/linux/Makefile"
echo "=== caihong_defconfig SQUASHFS / SECURITY / APPARMOR / LOCALVERSION / FIRMWARE / CRYPTO ==="
grep -E "SQUASHFS|SECURITY|APPARMOR|LOCALVERSION|XZ_DEC|LZO|LZ4|FUSE|OVERLAY|BLK_DEV_LOOP|CGROUPS|NAMESPACES|SECCOMP" "$BUILD_ROOT/linux/arch/arm64/configs/caihong_defconfig" || true
