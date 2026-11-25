#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOTFS_REPO="${ROOTFS_REPO:-$WORKSPACE/caihong-linux-rootfs}"
FIRMWARE_DIR="$ROOTFS_REPO/firmware"
CMDLINE_FILE="$ROOTFS_REPO/config/caihong-direct-root-cmdline.txt"
VERIFY_SCRIPT="$ROOTFS_REPO/scripts/verify-caihong-release.py"

BUILD_ROOT="/var/cache/caihong_kernel_build"
LINUX_DIR="$BUILD_ROOT/linux"
MKBOOTIMG="$BUILD_ROOT/mkbootimg/mkbootimg.py"
KERNEL_OUT="$BUILD_ROOT/out"
MODULE_TREE="$BUILD_ROOT/modules-current"
ARTIFACT_BOOT="$BUILD_ROOT/caihong-boot-linux.img"
ARTIFACT_MANIFEST="$BUILD_ROOT/caihong-boot-linux.manifest.json"
DEPLOY_BOOT="$WORKSPACE/deploy/boot/caihong-boot-linux.img"
DEPLOY_BOOT_ORIG="$WORKSPACE/deploy/boot/caihong-boot-linux.img.orig"

JOBS="$(nproc)"
EARLY_FIRMWARE="qcom/gen70900_sqe.fw qcom/gmu_gen70900.bin"

echo "[1/7] Backing up original deploy boot image (if needed) & verifying firmware checksums..."
if [ -f "$DEPLOY_BOOT" ] && [ ! -f "$DEPLOY_BOOT_ORIG" ]; then
    cp -a "$DEPLOY_BOOT" "$DEPLOY_BOOT_ORIG"
    echo "Backed up original boot image to $DEPLOY_BOOT_ORIG"
fi

(cd "$FIRMWARE_DIR" && sha256sum -c SHA256SUMS >/dev/null)
echo "Firmware SHA256SUMS OK."

echo "[1b/7] Applying Caihong kernel fixes (144Hz panel, PM8550 torch ires, dynamic pogo inputs)..."
python3 "$WORKSPACE/scripts/patch_nt36532_144hz.py" \
    "$LINUX_DIR/drivers/gpu/drm/panel/panel-novatek-nt36532.c"
for patch_name in \
    leds-qcom-flash-pm8550-torch-ires.patch \
    oneplus-pogo-dynamic-input.patch; do
    patch_file="$WORKSPACE/scripts/patches/$patch_name"
    if git -C "$LINUX_DIR" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        echo "  Already applied: $patch_name"
    else
        git -C "$LINUX_DIR" apply "$patch_file"
        echo "  Applied: $patch_name"
    fi
done

echo "[2/7] Configuring kernel with caihong_defconfig + SQUASHFS_XZ/LZ4/LZO/XATTR..."
mkdir -p "$KERNEL_OUT"
make -C "$LINUX_DIR" O="$KERNEL_OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc \
    caihong_defconfig

"$LINUX_DIR/scripts/config" --file "$KERNEL_OUT/.config" \
    --enable CONFIG_SQUASHFS \
    --enable CONFIG_SQUASHFS_XZ \
    --enable CONFIG_SQUASHFS_XATTR \
    --enable CONFIG_SQUASHFS_LZ4 \
    --enable CONFIG_SQUASHFS_LZO

make -C "$LINUX_DIR" O="$KERNEL_OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc \
    olddefconfig

for cfg in \
    CONFIG_DEVTMPFS=y \
    CONFIG_DEVTMPFS_MOUNT=y \
    CONFIG_EFI_PARTITION=y \
    CONFIG_SCSI=y \
    CONFIG_BLK_DEV_SD=y \
    CONFIG_SCSI_UFSHCD=y \
    CONFIG_SCSI_UFS_QCOM=y \
    CONFIG_PHY_QCOM_QMP_UFS=y \
    CONFIG_EXT4_FS=y \
    CONFIG_FW_LOADER_COMPRESS=y \
    CONFIG_FW_LOADER_COMPRESS_XZ=y \
    CONFIG_INPUT_JOYDEV=y \
    CONFIG_INPUT_UINPUT=y \
    CONFIG_SQUASHFS=y \
    CONFIG_SQUASHFS_XZ=y \
    CONFIG_SQUASHFS_XATTR=y \
    CONFIG_SQUASHFS_LZ4=y \
    CONFIG_SQUASHFS_LZO=y; do
    if ! grep -Fxq "$cfg" "$KERNEL_OUT/.config"; then
        echo "ERROR: Missing required kernel config: $cfg" >&2
        exit 1
    fi
done
echo "All required configs including CONFIG_SQUASHFS_XZ=y verified in .config."

echo "[3/7] Compiling Image, modules, and qcom/sm8650-oneplus-caihong.dtb with -j$JOBS..."
make -C "$LINUX_DIR" O="$KERNEL_OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc \
    CONFIG_EXTRA_FIRMWARE="$EARLY_FIRMWARE" \
    CONFIG_EXTRA_FIRMWARE_DIR="$FIRMWARE_DIR" \
    -j"$JOBS" Image modules qcom/sm8650-oneplus-caihong.dtb

KVER="$(make -s -C "$LINUX_DIR" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)"
echo "Built kernel release: $KVER"

echo "[4/7] Installing modules into $MODULE_TREE..."
rm -rf "$MODULE_TREE"
mkdir -p "$MODULE_TREE"
make -C "$LINUX_DIR" O="$KERNEL_OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc \
    INSTALL_MOD_PATH="$MODULE_TREE" modules_install

echo "[5/7] Building Android boot v2 image ($ARTIFACT_BOOT)..."
CMDLINE="$(tr -d '\r\n' < "$CMDLINE_FILE")"
python3 "$MKBOOTIMG" \
    --kernel "$KERNEL_OUT/arch/arm64/boot/Image" \
    --dtb "$KERNEL_OUT/arch/arm64/boot/dts/qcom/sm8650-oneplus-caihong.dtb" \
    --cmdline "$CMDLINE" \
    --base 0x0 \
    --kernel_offset 0x8000 \
    --ramdisk_offset 0x1000000 \
    --second_offset 0xf00000 \
    --tags_offset 0x100 \
    --dtb_offset 0x4000000 \
    --pagesize 4096 \
    --header_version 2 \
    --os_version 16.0.0 \
    --os_patch_level 2026-06 \
    --output "$ARTIFACT_BOOT"

echo "[6/7] Running verify-caihong-release.py..."
python3 "$VERIFY_SCRIPT" \
    --kernel "$KERNEL_OUT/arch/arm64/boot/Image" \
    --dtb "$KERNEL_OUT/arch/arm64/boot/dts/qcom/sm8650-oneplus-caihong.dtb" \
    --config "$KERNEL_OUT/.config" \
    --module-tree "$MODULE_TREE" \
    --firmware-dir "$FIRMWARE_DIR" \
    --manifest "$ARTIFACT_MANIFEST" \
    --root-partlabel linux \
    "$ARTIFACT_BOOT"

echo "[7/7] Copying verified boot image to $DEPLOY_BOOT and checking IKCFG inside boot image..."
cp -f "$ARTIFACT_BOOT" "$DEPLOY_BOOT"
python3 "$WORKSPACE/scripts/check_boot_cfg.py" "$DEPLOY_BOOT" || true
ls -lh "$DEPLOY_BOOT" "$ARTIFACT_BOOT"
echo "KERNEL_BUILD_DONE:$KVER"
