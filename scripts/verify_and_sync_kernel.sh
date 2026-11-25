#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOTFS_REPO="${ROOTFS_REPO:-$WORKSPACE/caihong-linux-rootfs}"
FIRMWARE_DIR="$ROOTFS_REPO/firmware"
VERIFY_SCRIPT="$ROOTFS_REPO/scripts/verify-caihong-release.py"

BUILD_ROOT="/var/cache/caihong_kernel_build"
KERNEL_OUT="$BUILD_ROOT/out"
MODULE_TREE="$BUILD_ROOT/modules-current"
ARTIFACT_BOOT="$BUILD_ROOT/caihong-boot-linux.img"
ARTIFACT_MANIFEST="$BUILD_ROOT/caihong-boot-linux.manifest.json"
DEPLOY_BOOT="$WORKSPACE/deploy/boot/caihong-boot-linux.img"
BACKUP_BOOT="${BACKUP_BOOT:-}"

echo "[1/3] Running verify-caihong-release.py..."
python3 "$VERIFY_SCRIPT" \
    --kernel "$KERNEL_OUT/arch/arm64/boot/Image" \
    --dtb "$KERNEL_OUT/arch/arm64/boot/dts/qcom/sm8650-oneplus-caihong.dtb" \
    --config "$KERNEL_OUT/.config" \
    --module-tree "$MODULE_TREE" \
    --firmware-dir "$FIRMWARE_DIR" \
    --manifest "$ARTIFACT_MANIFEST" \
    --root-partlabel linux \
    "$ARTIFACT_BOOT"

echo "[2/3] Deploying verified boot image to deploy/boot..."
cp -f "$ARTIFACT_BOOT" "$DEPLOY_BOOT"
if [ -n "$BACKUP_BOOT" ]; then
    mkdir -p "$(dirname "$BACKUP_BOOT")"
    cp -f "$ARTIFACT_BOOT" "$BACKUP_BOOT"
fi
python3 "$WORKSPACE/scripts/check_boot_cfg.py" "$DEPLOY_BOOT"

echo "[3/3] Checking new kernel release and syncing modules to /var/cache/ubuntu_kde_build/usr/lib/modules..."
KVER="$(ls -1 "$MODULE_TREE/lib/modules")"
echo "New kernel release: $KVER"
if [ "$(echo "$KVER" | wc -l)" -ne 1 ]; then
    echo "ERROR: Expected single module release dir, got: $KVER" >&2
    exit 1
fi

rm -rf /var/cache/ubuntu_kde_build/usr/lib/modules/*
cp -a "$MODULE_TREE/lib/modules/$KVER" /var/cache/ubuntu_kde_build/usr/lib/modules/
chroot /var/cache/ubuntu_kde_build depmod -a "$KVER"
ls -la /var/cache/ubuntu_kde_build/usr/lib/modules/
ls -lh "$DEPLOY_BOOT" ${BACKUP_BOOT:+"$BACKUP_BOOT"}
