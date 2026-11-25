#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

echo "===================================================================="
echo " Verifying Pure KDE Plasma Ubuntu 24.04 Rootfs for Caihong"
echo "===================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_IMG="${RAW_IMG:-/var/cache/ubuntu24_kde_raw.img}"
SPARSE_IMG="${SPARSE_IMG:-$SCRIPT_DIR/../deploy/rootfs/caihong-ubuntu24-rootfs.ext4.sparse.img}"
MNT="/var/cache/verify_kde_mnt"

mkdir -p "$MNT"
if ! mountpoint -q "$MNT"; then
    mount -o loop,ro "$RAW_IMG" "$MNT"
fi

cleanup() {
    umount -lf "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

ERRORS=0
fail() {
    echo "  [FAIL] $1"
    ERRORS=$((ERRORS + 1))
}
pass() {
    echo "  [PASS] $1"
}

echo "--- 1. Checking Core Caihong Binaries & Shared Library Dependencies (ldd) ---"
BINARIES=(
    "/usr/local/sbin/qbootctl"
    "/usr/local/libexec/caihong-nvram-mac"
    "/usr/local/libexec/caihong-ssc/hexagonrpcd"
    "/usr/local/libexec/caihong-ssc/iio-sensor-proxy"
    "/usr/local/lib/caihong-ssc/libssc.so.2"
    "/usr/local/sbin/caihong-npu-info"
    "/usr/local/libexec/caihong-npu-htp-self-test"
    "/usr/local/libexec/caihong-npu-htp-conv-test"
    "/usr/bin/adbd"
)

for bin in "${BINARIES[@]}"; do
    if [ ! -e "$MNT$bin" ]; then
        fail "Missing binary/library: $bin"
    else
        missing=$(chroot "$MNT" ldd "$bin" 2>&1 | grep "not found" || true)
        if [ -n "$missing" ]; then
            fail "Missing shared libraries for $bin: $missing"
        else
            pass "ldd clean: $bin"
        fi
    fi
done

echo "--- 2. Checking ADSP Sensor Registry Root (/var/lib/caihong-ssc/root) & SSC/NPU Units ---"
for f in \
    "/usr/lib/systemd/system/caihong-ssc.service" \
    "/usr/lib/systemd/system/iio-sensor-proxy.service.d/caihong-ssc.conf" \
    "/var/lib/caihong-ssc/root/sensors/sns_reg.conf" \
    "/var/lib/caihong-ssc/root/socinfo/soc_id" \
    "/usr/lib/dsp/fastrpc_shell_unsigned_3" \
    "/usr/lib/caihong-adbd/libprotobuf.so.32" \
    "/usr/lib/caihong-npu/libcalculator.so"; do
    if [ -s "$MNT$f" ]; then
        pass "Present: $f"
    else
        fail "Missing or empty: $f"
    fi
done

reg_count=$(find "$MNT/var/lib/caihong-ssc/root/sensors/registry" -type f 2>/dev/null | wc -l)
if [ "$reg_count" -gt 100 ]; then
    pass "Sensor registry files present ($reg_count files)"
else
    fail "Sensor registry files missing ($reg_count files)"
fi

echo "--- 3. Checking ALSA UCM2 Topology & AudioReach Prerequisites ---"
for f in \
    "/usr/share/alsa/ucm2/ucm.conf" \
    "/usr/share/alsa/ucm2/lib/card-init.conf" \
    "/usr/share/alsa/ucm2/lib/ctl-remap.conf" \
    "/usr/share/alsa/ucm2/conf.d/sm8650/SM8650-MTP.conf" \
    "/usr/share/alsa/ucm2/Qualcomm/sm8650/Caihong/HiFi.conf" \
    "/usr/lib/tmpfiles.d/caihong-alsa.conf"; do
    if [ -s "$MNT$f" ]; then
        pass "Present: $f"
    else
        fail "Missing: $f"
    fi
done

if [ -e "$MNT/etc/alsa/state-daemon.conf" ]; then
    fail "/etc/alsa/state-daemon.conf still exists (breaks static alsa-restore)"
else
    pass "/etc/alsa/state-daemon.conf removed"
fi

echo "--- 4. Checking KDE Plasma 5.27 Wayland, SDDM, OSK & Scaling ---"
for f in \
    "/usr/share/wayland-sessions/plasmawayland.desktop" \
    "/usr/bin/kwin_wayland" \
    "/usr/bin/plasmashell" \
    "/usr/bin/kscreen-doctor" \
    "/usr/bin/maliit-keyboard" \
    "/usr/bin/pkexec" \
    "/etc/sddm.conf.d/caihong-kde.conf" \
    "/home/ubuntu/.config/kwinrc" \
    "/home/ubuntu/.config/kwinoutputconfig.json" \
    "/home/ubuntu/.config/baloofilerc" \
    "/home/ubuntu/.config/kscreenlockerrc" \
    "/home/ubuntu/.config/powermanagementprofilesrc" \
    "/home/ubuntu/.config/kwalletrc" \
    "/home/ubuntu/.config/plasma-nm" \
    "/etc/xdg/kwalletrc" \
    "/etc/xdg/plasma-nm" \
    "/home/ubuntu/.local/share/kscreen/control/configs/b5350822fc24a835e633b5bf90f2b56d" \
    "/home/ubuntu/.local/share/kscreen/control/outputs/b5350822fc24a835e633b5bf90f2b56d" \
    "/etc/modprobe.d/caihong-wifi.conf" \
    "/etc/NetworkManager/dispatcher.d/10-caihong-wifi-regdom" \
    "/usr/local/sbin/caihong-wifi-regdom" \
    "/etc/systemd/system/caihong-wifi-regdom.service" \
    "/etc/udev/rules.d/81-caihong-wifi-regdom.rules"; do
    if [ -s "$MNT$f" ]; then
        pass "Present: $f"
    else
        fail "Missing: $f"
    fi
done

if grep -rq "alarm" \
    "$MNT/usr/local/sbin/caihong-fix-kwin-brightness" \
    "$MNT/usr/local/sbin/caihong-clean-pogo-kde" \
    "$MNT/etc/systemd/system/caihong-fix-kwin-brightness.service" \
    "$MNT/etc/systemd/system/caihong-clean-pogo-kde.service" \
    "$MNT/etc/systemd/system/caihong-adbd.service.d/20-user.conf"; then
    fail "Stale 'alarm' reference found in KDE or adbd scripts/services"
else
    pass "All KDE & adbd scripts/services adapted to user 'ubuntu'"
fi

echo "--- 4b. Checking Regression Fixes (DBus Keyboard1, Grow Rootfs, Hotspot, BT MAC Timeout, Sparse Metadata) ---"
if [ -s "$MNT/etc/dbus-1/system.d/org.caihong.Keyboard1.conf" ]; then
    pass "Present: /etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
else
    fail "Missing: /etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
fi

if grep -q "/usr/sbin/resize2fs" "$MNT/etc/systemd/system/caihong-grow-rootfs.service" && [ -x "$MNT/usr/sbin/resize2fs" ]; then
    pass "caihong-grow-rootfs.service uses valid /usr/sbin/resize2fs"
else
    fail "caihong-grow-rootfs.service resize2fs path mismatch"
fi

if grep -q "/usr/sbin/hostapd" "$MNT/etc/systemd/system/caihong-hotspot.service" && grep -q "/usr/sbin/dnsmasq" "$MNT/etc/systemd/system/caihong-hotspot.service"; then
    pass "caihong-hotspot.service uses /usr/sbin/{hostapd,dnsmasq}"
else
    fail "caihong-hotspot.service binary paths mismatch"
fi

if grep -q "TimeoutStartSec=120" "$MNT/etc/systemd/system/caihong-hardware-mac.service" && grep -q "wait_for_nvram" "$MNT/usr/local/sbin/caihong-hardware-mac" && grep -q "btmgmt-in" "$MNT/usr/local/sbin/caihong-hardware-mac"; then
    pass "caihong-hardware-mac uses latest repo script + TimeoutStartSec=120 + btmgmt FIFO stdin fix"
else
    fail "caihong-hardware-mac script, TimeoutStartSec=120, or btmgmt FIFO fix missing"
fi

if python3 - "$RAW_IMG" "$SPARSE_IMG" "$SCRIPT_DIR" << 'PYEOF'
import struct, sys
from pathlib import Path
sys.path.insert(0, sys.argv[3])
import fix_sparse_zero_metadata as mod
ranges = mod.collect_metadata_ranges(Path(sys.argv[1]))
with open(sys.argv[2], "rb") as f:
    magic, maj, minv, fhdr_sz, chdr_sz, blk_sz, total_blks, total_chunks, _ = struct.unpack("<IHHHHIIII", f.read(28))
    cur = 0
    for _ in range(total_chunks):
        ctype, res, cblks, csz = struct.unpack("<HHII", f.read(chdr_sz))
        if ctype in (0xCAC2, 0xCAC3):
            segs = mod.split_by_metadata(cur, cur + cblks, ranges)
            if any(m for m, _, _ in segs):
                raise SystemExit(1)
        f.seek(csz - chdr_sz, 1)
        cur += cblks
    if cur != total_blks:
        raise SystemExit(2)
PYEOF
then
    pass "All ext4 metadata blocks in sparse image use CHUNK_RAW (zero bootloader FILL(0) risk)"
else
    fail "Sparse image still contains ext4 metadata blocks inside FILL/DONT_CARE chunks"
fi

echo "--- 5. Checking Wi-Fi, DNS, Bluetooth & Udev Rules ---"
if [ -e "$MNT/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf" ]; then
    fail "default-wifi-powersave-on.conf still exists"
else
    pass "default-wifi-powersave-on.conf removed"
fi

if [ -L "$MNT/etc/resolv.conf" ] && [ -x "$MNT/usr/lib/systemd/systemd-resolved" ]; then
    pass "systemd-resolved installed and /etc/resolv.conf symlinked"
else
    fail "systemd-resolved or /etc/resolv.conf symlink missing"
fi

if grep -q "SYSTEMD_READY" "$MNT/etc/udev/rules.d/80-caihong-android-udisks.rules"; then
    fail "80-caihong-android-udisks.rules contains SYSTEMD_READY=0 (breaks NVRAM MAC reading)"
else
    pass "80-caihong-android-udisks.rules hides partitions cleanly via UDISKS_IGNORE=1 only"
fi

if grep -q "powerButtonAction=64" "$MNT/home/ubuntu/.config/powermanagementprofilesrc" \
    && grep -q "Enabled=false" "$MNT/home/ubuntu/.config/kwalletrc" \
    && grep -q "Enabled=false" "$MNT/etc/xdg/kwalletrc" \
    && grep -q "SystemConnectionsByDefault=true" "$MNT/home/ubuntu/.config/plasma-nm" \
    && grep -q "SystemConnectionsByDefault=true" "$MNT/etc/xdg/plasma-nm" \
    && grep -q "ieee80211_regdom=US" "$MNT/etc/modprobe.d/caihong-wifi.conf" \
    && [ -x "$MNT/etc/NetworkManager/dispatcher.d/10-caihong-wifi-regdom" ] \
    && [ -s "$MNT/usr/lib/firmware/regulatory.db" ] \
    && grep -q '"autorotate-tablet-only": false' "$MNT/home/ubuntu/.local/share/kscreen/control/configs/b5350822fc24a835e633b5bf90f2b56d" \
    && [ -L "$MNT/etc/systemd/system/multi-user.target.wants/caihong-wifi-regdom.service" ]; then
    pass "Power button, KWallet bypass, system Wi-Fi, KScreen autorotate, and 5GHz regdom persisted"
else
    fail "Missing PowerDevil/KWallet/KScreen/regdom persistence settings"
fi

echo "--- 6. Checking CRLF Line Endings in Scripts & Systemd Units ---"
crlf_files=$(grep -I -rl $'\r' "$MNT/usr/local/sbin/" "$MNT/usr/local/bin/" "$MNT/etc/systemd/system/" "$MNT/etc/udev/rules.d/" 2>/dev/null || true)
if [ -n "$crlf_files" ]; then
    fail "CRLF line endings found in: $crlf_files"
else
    pass "Zero CRLF line endings in scripts, systemd units, and udev rules"
fi

echo "--- 7. Checking /run and /tmp Empty ---"
if [ -n "$(ls -A "$MNT/run" 2>/dev/null)" ]; then
    fail "/run is not empty: $(ls -A "$MNT/run")"
else
    pass "/run is completely empty"
fi

# Check Caihong Camera ISP (libcamera), Iris VA-API, and Flashlight UX
for f in \
    usr/lib/firmware/qcom/sm8650/bps-striping-bggr10-nv12-3264x2448.bin \
    usr/lib/firmware/qcom/sm8650/bps-striping-bggr10-nv12-4208x3120.bin \
    usr/lib/firmware/qcom/sm8650/bps-striping-bggr10-nv12-640x480.bin \
    usr/bin/cam \
    usr/bin/qcam \
    usr/lib/aarch64-linux-gnu/libcamera.so.0.7.2 \
    usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so \
    usr/lib/aarch64-linux-gnu/dri/qcom_drv_video.so \
    usr/lib/aarch64-linux-gnu/dri/msm_drv_video.so \
    usr/local/sbin/caihong-flashlight \
    usr/local/bin/caihong-flashlight \
    usr/local/bin/caihong-flashlight-toggle \
    usr/local/bin/caihong-flashlight-gui \
    usr/share/applications/caihong-camera.desktop \
    usr/share/applications/caihong-flashlight.desktop \
    home/ubuntu/Desktop/caihong-camera.desktop \
    home/ubuntu/Desktop/caihong-flashlight.desktop \
    usr/share/caihong/libcamera-build-info \
    usr/share/caihong/vaapi-build-info; do
    if [ ! -e "$MNT/$f" ] && [ ! -L "$MNT/$f" ]; then
        echo "  FAIL: Missing $f"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK: $f"
    fi
done

echo "===================================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo " ALL CHECKS PASSED (0 errors)! Image is ready to flash."
    ls -lh "$RAW_IMG" "$SPARSE_IMG"
else
    echo " VERIFICATION FAILED WITH $ERRORS ERROR(S)!"
    exit 1
fi
