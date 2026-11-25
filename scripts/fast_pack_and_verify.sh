#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="${ROOTFS:-/var/cache/ubuntu_kde_build}"
ARCH_MNT="${ARCH_MNT:-/var/cache/arch_mnt}"
WORKSPACE="${WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
REPO_ARCH="${REPO_ARCH:-$WORKSPACE/caihong-linux-rootfs/rootfs/archlinuxarm}"
RAW_IMG="${RAW_IMG:-/var/cache/ubuntu24_kde_raw.img}"
SPARSE_LOCAL="${SPARSE_LOCAL:-/var/cache/caihong-ubuntu24-kde.ext4.sparse.img}"
SPARSE_OUT="${SPARSE_OUT:-$WORKSPACE/deploy/rootfs/caihong-ubuntu24-rootfs.ext4.sparse.img}"
ADB_PUBKEY="${ADB_PUBKEY:-$HOME/.android/adbkey.pub}"

mkdir -p "$ARCH_MNT" "$(dirname "$SPARSE_OUT")"
if ! mountpoint -q "$ARCH_MNT" && [ -n "${ARCH_RAW:-}" ]; then
    mount -o loop,ro "$ARCH_RAW" "$ARCH_MNT"
fi

umount -lf /var/cache/verify_kde_mnt 2>/dev/null || true

echo "[1/5] Copying caihong-adbd, caihong-npu, DBus policy, and latest Caihong units/scripts..."
cp -a "$ARCH_MNT/usr/lib/caihong-adbd" "$ROOTFS/usr/lib/"
cp -a "$ARCH_MNT/usr/lib/caihong-npu" "$ROOTFS/usr/lib/"
cp -a "$ARCH_MNT/usr/lib/libQnnHtp"* "$ROOTFS/usr/lib/"
cp -a "$ARCH_MNT/usr/share/caihong-npu" "$ROOTFS/usr/share/"
cp -a "$ARCH_MNT/usr/share/caihong" "$ROOTFS/usr/share/" 2>/dev/null || true
cp -a "$ARCH_MNT/usr/lib/dri/msm_drv_video.so" "$ROOTFS/usr/lib/dri/" 2>/dev/null || true
cp -a "$ARCH_MNT/usr/lib/dri/msm_drv_video.so" "$ROOTFS/usr/lib/aarch64-linux-gnu/dri/" 2>/dev/null || true

# Fix 1: DBus policy for caihong-keyboard.service (org.caihong.Keyboard1)
mkdir -p "$ROOTFS/etc/dbus-1/system.d"
cp -f "$REPO_ARCH/etc/dbus-1/system.d/org.caihong.Keyboard1.conf" "$ROOTFS/etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
sed -i 's/\r$//' "$ROOTFS/etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
chmod 644 "$ROOTFS/etc/dbus-1/system.d/org.caihong.Keyboard1.conf"

# Fix 2: Sync newer Caihong scripts & units from git repo (incl. TimeoutStartSec=120 caihong-hardware-mac)
for f in \
    usr/local/sbin/caihong-flashlight \
    usr/local/sbin/caihong-hardware-mac \
    usr/local/sbin/caihong-keyboard \
    usr/local/sbin/caihong-charge \
    usr/local/sbin/caihong-clean-pogo-kde \
    usr/local/sbin/caihong-fix-kwin-brightness \
    etc/systemd/system/caihong-hardware-mac.service \
    etc/systemd/system/caihong-keyboard.service \
    etc/systemd/system/caihong-charge.service \
    etc/systemd/system/caihong-clean-pogo-kde.service \
    etc/systemd/system/caihong-fix-kwin-brightness.service; do
    if [ -f "$WORKSPACE/scripts/rootfs_overlay/$f" ]; then
        cp -f "$WORKSPACE/scripts/rootfs_overlay/$f" "$ROOTFS/$f"
    else
        cp -f "$REPO_ARCH/$f" "$ROOTFS/$f"
    fi
    sed -i 's/\r$//' "$ROOTFS/$f"
done
cp -f "$WORKSPACE/caihong-linux-rootfs/rootfs/armada/etc/systemd/system/caihong-bluetooth-late-autostart.timer" \
    "$ROOTFS/etc/systemd/system/caihong-bluetooth-late-autostart.timer"
sed -i 's/\r$//' "$ROOTFS/etc/systemd/system/caihong-bluetooth-late-autostart.timer"
chmod 755 \
    "$ROOTFS/usr/local/sbin/caihong-flashlight" \
    "$ROOTFS/usr/local/sbin/caihong-hardware-mac" \
    "$ROOTFS/usr/local/sbin/caihong-keyboard" \
    "$ROOTFS/usr/local/sbin/caihong-charge" \
    "$ROOTFS/usr/local/sbin/caihong-clean-pogo-kde" \
    "$ROOTFS/usr/local/sbin/caihong-fix-kwin-brightness"
chmod 644 "$ROOTFS/etc/systemd/system/caihong-"*.service "$ROOTFS/etc/systemd/system/caihong-"*.timer 2>/dev/null || true

sed -i 's/\r$//' "$WORKSPACE/scripts/patch_hardware_mac_btmgmt.py"
python3 "$WORKSPACE/scripts/patch_hardware_mac_btmgmt.py" "$ROOTFS/usr/local/sbin/caihong-hardware-mac"

# Fix 3: Rewrite 'alarm' -> 'ubuntu' in KDE & ADB configs, and install /home/ubuntu/.android/adb_keys
sed -i \
    -e 's#/home/alarm#/home/ubuntu#g' \
    -e 's/machine=alarm@/machine=ubuntu@/g' \
    -e 's/-o alarm -g alarm/-o ubuntu -g ubuntu/g' \
    -e 's/chown alarm:alarm/chown ubuntu:ubuntu/g' \
    -e 's/alarm user/ubuntu user/g' \
    -e 's/^User=alarm$/User=ubuntu/' \
    -e 's/^Group=alarm$/Group=ubuntu/' \
    -e 's/^Environment=ADBD_USER=alarm$/Environment=ADBD_USER=ubuntu/' \
    "$ROOTFS/etc/systemd/system/caihong-clean-pogo-kde.service" \
    "$ROOTFS/usr/local/sbin/caihong-clean-pogo-kde" \
    "$ROOTFS/etc/systemd/system/caihong-fix-kwin-brightness.service" \
    "$ROOTFS/usr/local/sbin/caihong-fix-kwin-brightness" \
    "$ROOTFS/etc/systemd/system/caihong-adbd.service.d/20-user.conf"

if [ -n "$ADB_PUBKEY" ] && [ -f "$ADB_PUBKEY" ]; then
    mkdir -p "$ROOTFS/home/ubuntu/.android" "$ROOTFS/data/misc/adb" "$ROOTFS/root/.android"
    cat "$ADB_PUBKEY" > "$ROOTFS/home/ubuntu/.android/adb_keys"
    cat "$ADB_PUBKEY" > "$ROOTFS/data/misc/adb/adb_keys"
    cat "$ADB_PUBKEY" > "$ROOTFS/root/.android/adbkey.pub"
    sed -i 's/\r$//' "$ROOTFS/home/ubuntu/.android/adb_keys" "$ROOTFS/data/misc/adb/adb_keys" "$ROOTFS/root/.android/adbkey.pub"
    chmod 600 "$ROOTFS/home/ubuntu/.android/adb_keys" "$ROOTFS/data/misc/adb/adb_keys" "$ROOTFS/root/.android/adbkey.pub"
    chroot "$ROOTFS" chown -R ubuntu:ubuntu /home/ubuntu/.android
fi

# Fix 4: Ubuntu installs resize2fs, hostapd, and dnsmasq in /usr/sbin (not /usr/bin)
sed -i 's#/usr/bin/resize2fs#/usr/sbin/resize2fs#g' \
    "$ROOTFS/etc/systemd/system/caihong-grow-rootfs.service"
sed -i \
    -e 's#/usr/bin/hostapd#/usr/sbin/hostapd#g' \
    -e 's#/usr/bin/dnsmasq#/usr/sbin/dnsmasq#g' \
    "$ROOTFS/etc/systemd/system/caihong-hotspot.service"

cat << 'EOF' > "$ROOTFS/etc/ld.so.conf.d/caihong.conf"
/usr/local/lib
/usr/local/lib/caihong-ssc
/usr/lib/caihong-adbd
/usr/lib/caihong-npu
/usr/lib/caihong-npu/qnn
/usr/lib
EOF
chroot "$ROOTFS" ldconfig

rm -rf "$ROOTFS/run/"* "$ROOTFS/tmp/"* 2>/dev/null || true
: > "$ROOTFS/etc/machine-id"

echo "[2/5] Packing ext4 image (sized dynamically, grown to 50G on first boot)..."
rm -f "$RAW_IMG" "$SPARSE_LOCAL"
used_bytes=$(du -sx --block-size=1 "$ROOTFS" | awk 'NR == 1 { print $1 }')
round_bytes=$((256 * 1024 * 1024))
required_bytes=$((used_bytes + 768 * 1024 * 1024))
image_bytes=$(((required_bytes + round_bytes - 1) / round_bytes * round_bytes))
truncate -s "$image_bytes" "$RAW_IMG"
mkfs.ext4 -q -F -L linux -m 0 \
    -O ^metadata_csum_seed \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    -d "$ROOTFS" "$RAW_IMG"

e2fsck -fy "$RAW_IMG" || true

echo "[3/5] Converting to Android sparse image and hardening zeroed ext4 metadata..."
img2simg "$RAW_IMG" "$SPARSE_LOCAL"
sed -i 's/\r$//' "$WORKSPACE/scripts/fix_sparse_zero_metadata.py"
python3 "$WORKSPACE/scripts/fix_sparse_zero_metadata.py" "$RAW_IMG" "$SPARSE_LOCAL"

echo "[4/5] Copying verified sparse image to Windows output path..."
cp -f "$SPARSE_LOCAL" "$SPARSE_OUT"

echo "[5/5] Running full verification..."
sed -i 's/\r$//' "$WORKSPACE/scripts/verify_ubuntu_kde_rootfs.sh"
bash "$WORKSPACE/scripts/verify_ubuntu_kde_rootfs.sh"
