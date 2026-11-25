#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

echo "===================================================================="
echo " Building Clean Pure KDE Plasma Ubuntu 24.04 Rootfs for Caihong"
echo "===================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BASE_TARBALL="${BASE_TARBALL:-$WORKSPACE/deploy/rootfs/ubuntu-base-24.04.5-base-arm64.tar.gz}"
MODULES_PKG="${MODULES_PKG:-$WORKSPACE/deploy/boot/linux-caihong-modules.pkg.tar.zst}"
PLATFORM_TAR="${PLATFORM_TAR:-$WORKSPACE/deploy/boot/caihong-platform-assets.tar.zst}"
ARCH_RAW="${ARCH_RAW:-/var/cache/arch.raw.img}"
OUT_DIR="${OUT_DIR:-$WORKSPACE/deploy/rootfs}"
RAW_IMG="${RAW_IMG:-/var/cache/ubuntu24_kde_raw.img}"
SPARSE_IMG="${SPARSE_IMG:-$OUT_DIR/caihong-ubuntu24-rootfs.ext4.sparse.img}"
ADB_PUBKEY="${ADB_PUBKEY:-$HOME/.android/adbkey.pub}"

ARCH_MNT="/var/cache/arch_mnt"
ROOTFS="/var/cache/ubuntu_kde_build"
IMG_MNT="/var/cache/ubuntu_kde_mnt"

mkdir -p "$OUT_DIR" "$ARCH_MNT" "$ROOTFS" "$IMG_MNT"

# 1. Mount working Arch Linux reference image read-only
if ! mountpoint -q "$ARCH_MNT"; then
    mount -o loop,ro "$ARCH_RAW" "$ARCH_MNT"
fi

# Clean old GNOME image
umount -lf /tmp/ubu_mnt 2>/dev/null || true
rm -f "$OUT_DIR/ubu_raw.img" "$OUT_DIR/caihong-ubuntu24-gnome.ext4.sparse.img"
umount -R "$ROOTFS/dev/pts" "$ROOTFS/dev" "$ROOTFS/sys" "$ROOTFS/proc" 2>/dev/null || true

if [ ! -x "$ROOTFS/usr/bin/plasmashell" ]; then
    rm -rf "$ROOTFS"
    mkdir -p "$ROOTFS"
    echo "[1/10] Extracting clean Ubuntu 24.04.5 ARM64 base tarball..."
    tar --numeric-owner -xzpf "$BASE_TARBALL" -C "$ROOTFS"
else
    echo "[1/10] Reusing existing clean Ubuntu 24.04.5 ARM64 base in $ROOTFS..."
fi

# Prepare chroot mounts
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"

cleanup() {
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
    umount -lf "$IMG_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Temporary DNS for chroot apt
rm -f "$ROOTFS/etc/resolv.conf"
cat /etc/resolv.conf > "$ROOTFS/etc/resolv.conf"

# Policy-rc.d to prevent daemons starting inside chroot
cat << 'EOF' > "$ROOTFS/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
chmod +x "$ROOTFS/usr/sbin/policy-rc.d"

# Configure fastest ARM64 Ubuntu mirror (Aliyun)
cat << 'EOF' > "$ROOTFS/etc/apt/sources.list.d/ubuntu.sources"
Types: deb
URIs: http://mirrors.aliyun.com/ubuntu-ports
Suites: noble noble-updates noble-backports noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

if [ ! -x "$ROOTFS/usr/bin/plasmashell" ]; then
    echo "[2/10] Installing System Core, Qualcomm QMI/QRTR/ALSA-UCM, and Pure KDE Plasma Wayland..."
    chroot "$ROOTFS" apt-get update -y

    # Install core system + hardware + audio + networking + pure KDE Plasma Wayland packages
    chroot "$ROOTFS" apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-resolved systemd-timesyncd \
        udev dbus dbus-user-session dbus-x11 \
        sudo polkitd pkexec \
        kmod u-boot-tools initramfs-tools \
        iproute2 iputils-ping net-tools ethtool \
        network-manager wpasupplicant wireless-regdb hostapd dnsmasq-base iw rfkill \
        bluez bluez-tools \
        alsa-utils alsa-ucm-conf rtkit \
        pipewire pipewire-pulse pipewire-alsa wireplumber libspa-0.2-bluetooth \
        iio-sensor-proxy \
        libqmi-glib5 libqrtr-glib0 libprotobuf-c1 libbsd0 libyaml-0-2 \
        libdrm2 libdrm-freedreno1 libgbm1 \
        mesa-vulkan-drivers mesa-va-drivers libgl1-mesa-dri libegl-mesa0 libgles2 \
        vainfo vulkan-tools \
        power-profiles-daemon upower udisks2 \
        parted e2fsprogs dosfstools zstd xz-utils file psmisc lsof procps htop \
        openssh-server ca-certificates curl wget nano vim-tiny git \
        python3 python3-gi python3-dbus gir1.2-glib-2.0 \
        locales tzdata keyboard-configuration console-setup \
        fonts-noto-cjk fonts-noto-color-emoji fonts-dejavu-core \
        sddm sddm-theme-breeze \
        plasma-desktop plasma-workspace plasma-workspace-wayland \
        systemsettings kinfocenter plasma-systemmonitor \
        kwin-wayland kwin-x11 kwin-style-breeze \
        breeze breeze-icon-theme breeze-cursor-theme \
        kde-cli-tools kde-config-gtk-style kde-config-screenlocker \
        kscreen libkf5screen-bin libqt5sensors5 \
        plasma-nm plasma-pa bluedevil powerdevil \
        polkit-kde-agent-1 xdg-desktop-portal xdg-desktop-portal-kde xdg-user-dirs \
        maliit-keyboard qtvirtualkeyboard-plugin qtwayland5 layer-shell-qt \
        fcitx5 fcitx5-chinese-addons kde-config-fcitx5 \
        dolphin konsole kate kde-spectacle ark okular gwenview kcalc \
        xwayland xserver-xorg-core xserver-xorg-input-libinput \
        v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        libgstreamer-plugins-base1.0-0 libevent-pthreads-2.1-7t64 libyuv0 libva2 \
        libqt6widgets6t64 libqt6openglwidgets6t64 qt6-wayland libdw1t64 libunwind8 \
        libnotify-bin xdg-utils
else
    echo "[2/10] Packages already installed in $ROOTFS, skipping apt-get..."
fi

# Remove Fcitx5 XDG autostart so KWin Wayland manages Maliit touch OSK cleanly without conflict
rm -f "$ROOTFS/etc/xdg/autostart/org.fcitx.Fcitx5.desktop"

chroot "$ROOTFS" apt-get clean

if [ ! -d "$ROOTFS/usr/lib/modules/7.3.0-g77f2f22ff4f9" ] || [ ! -d "$ROOTFS/usr/lib/firmware/qcom" ]; then
    echo "[3/10] Installing Kernel 7.3.0-g77f2f22ff4f9 modules and Firmware..."
    mkdir -p "$ROOTFS/usr/lib/modules"
    rsync -aHAX --numeric-ids "$ARCH_MNT/usr/lib/modules/" "$ROOTFS/usr/lib/modules/"
    mkdir -p "$ROOTFS/usr/lib/firmware"
    rsync -aHAX --numeric-ids --exclude='regulatory.db' --exclude='regulatory.db.p7s' \
        "$ARCH_MNT/usr/lib/firmware/" "$ROOTFS/usr/lib/firmware/"
else
    echo "[3/10] Kernel modules and Firmware already installed in $ROOTFS..."
fi

echo "[4/10] Overlaying Caihong Platform Assets, ALSA UCM2, SSC Sensor Root, and NPU Libraries..."
# Extract caihong-platform-assets.tar.zst AFTER alsa-ucm-conf so Caihong UCM2 sits cleanly on top of /usr/share/alsa/ucm2/lib/
tar --zstd --numeric-owner -xpf "$PLATFORM_TAR" -C "$ROOTFS"

# Copy all config/udev/systemd/alsa files from working Arch image that belong to Caihong platform
cp -a "$ARCH_MNT/etc/bluetooth/main.conf" "$ROOTFS/etc/bluetooth/main.conf"
cp -a "$ARCH_MNT/etc/caihong-hotspot.conf" "$ROOTFS/etc/caihong-hotspot.conf"
cp -a "$ARCH_MNT/etc/caihong-pen.json" "$ROOTFS/etc/caihong-pen.json"
cp -a "$ARCH_MNT/etc/dbus-1/system.d/"* "$ROOTFS/etc/dbus-1/system.d/" 2>/dev/null || true
cp -f "$WORKSPACE/caihong-linux-rootfs/rootfs/archlinuxarm/etc/dbus-1/system.d/org.caihong.Keyboard1.conf" "$ROOTFS/etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
sed -i 's/\r$//' "$ROOTFS/etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
chmod 644 "$ROOTFS/etc/dbus-1/system.d/org.caihong.Keyboard1.conf"
mkdir -p "$ROOTFS/etc/modules-load.d"
cp -a "$ARCH_MNT/etc/modules-load.d/caihong.conf" "$ROOTFS/etc/modules-load.d/caihong.conf"
mkdir -p "$ROOTFS/etc/NetworkManager/conf.d"
cp -a "$ARCH_MNT/etc/NetworkManager/conf.d/"* "$ROOTFS/etc/NetworkManager/conf.d/"
mkdir -p "$ROOTFS/etc/systemd/system.conf.d"
cp -a "$ARCH_MNT/etc/systemd/system.conf.d/"* "$ROOTFS/etc/systemd/system.conf.d/"
mkdir -p "$ROOTFS/etc/systemd/user"
cp -a "$ARCH_MNT/etc/systemd/user/"*.slice.d "$ROOTFS/etc/systemd/user/" 2>/dev/null || true
mkdir -p "$ROOTFS/etc/udev/rules.d"
cp -a "$ARCH_MNT/etc/udev/rules.d/"* "$ROOTFS/etc/udev/rules.d/"
mkdir -p "$ROOTFS/etc/xdg"
cp -a "$ARCH_MNT/etc/xdg/bluedevilglobalrc" "$ROOTFS/etc/xdg/bluedevilglobalrc"
mkdir -p "$ROOTFS/usr/lib/tmpfiles.d"
cp -a "$ARCH_MNT/usr/lib/tmpfiles.d/caihong-alsa.conf" "$ROOTFS/usr/lib/tmpfiles.d/caihong-alsa.conf"
mkdir -p "$ROOTFS/usr/lib/udev/rules.d"
cp -a "$ARCH_MNT/usr/lib/udev/rules.d/"*caihong* "$ROOTFS/usr/lib/udev/rules.d/"

# Copy systemd units and drop-ins from working Arch image (/etc/systemd/system and /usr/lib/systemd/system)
cp -a "$ARCH_MNT/etc/systemd/system/caihong-"* "$ROOTFS/etc/systemd/system/"
for dropin_dir in "$ARCH_MNT/etc/systemd/system/"*.d; do
    if [ -d "$dropin_dir" ]; then
        cp -a "$dropin_dir" "$ROOTFS/etc/systemd/system/"
    fi
done
cp -a "$ARCH_MNT/usr/lib/systemd/system/caihong-ssc.service" "$ROOTFS/usr/lib/systemd/system/caihong-ssc.service"
mkdir -p "$ROOTFS/usr/lib/systemd/system/iio-sensor-proxy.service.d"
cp -a "$ARCH_MNT/usr/lib/systemd/system/iio-sensor-proxy.service.d/"* "$ROOTFS/usr/lib/systemd/system/iio-sensor-proxy.service.d/"

# Copy binaries from working Arch image (/usr/local/sbin, /usr/local/libexec, /usr/local/lib)
rsync -aHAX --numeric-ids "$ARCH_MNT/usr/local/" "$ROOTFS/usr/local/"

# Overlay newer Caihong scripts & units from git repo (including TimeoutStartSec=120 caihong-hardware-mac.service)
REPO_ARCH="$WORKSPACE/caihong-linux-rootfs/rootfs/archlinuxarm"
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

sed -i 's/\r$//' "$WORKSPACE/scripts/patch_hardware_mac_btmgmt.py"
python3 "$WORKSPACE/scripts/patch_hardware_mac_btmgmt.py" "$ROOTFS/usr/local/sbin/caihong-hardware-mac"

# Remove GNOME-only display-input helper as package-archlinuxarm-rootfs.sh does on KDE Plasma
rm -f "$ROOTFS/usr/local/sbin/caihong-display-input" \
      "$ROOTFS/etc/systemd/user/caihong-display-input.service" \
      "$ROOTFS/etc/xdg/autostart/caihong-display-input.desktop"

# CRITICAL FIX 1: Copy /var/lib/caihong-ssc/root so hexagonrpcd & ADSP never crash!
mkdir -p "$ROOTFS/var/lib/caihong-ssc"
rsync -aHAX --numeric-ids "$ARCH_MNT/var/lib/caihong-ssc/" "$ROOTFS/var/lib/caihong-ssc/"

# Copy Qualcomm Iris VA-API video driver & NPU FastRPC libraries into multiarch + /usr/lib
mkdir -p "$ROOTFS/usr/lib/dri" "$ROOTFS/usr/lib/aarch64-linux-gnu/dri" "$ROOTFS/usr/lib/dsp"
if [ -f "$ARCH_MNT/usr/lib/dri/qcom_drv_video.so" ]; then
    cp -a "$ARCH_MNT/usr/lib/dri/qcom_drv_video.so" "$ROOTFS/usr/lib/dri/"
    cp -a "$ARCH_MNT/usr/lib/dri/qcom_drv_video.so" "$ROOTFS/usr/lib/aarch64-linux-gnu/dri/"
fi
cp -a "$ARCH_MNT/usr/lib/libcdsprpc.so"* "$ROOTFS/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
cp -a "$ARCH_MNT/usr/lib/libcdsprpc.so"* "$ROOTFS/usr/lib/" 2>/dev/null || true
if [ -d "$ARCH_MNT/usr/lib/dsp" ]; then
    rsync -aHAX --numeric-ids "$ARCH_MNT/usr/lib/dsp/" "$ROOTFS/usr/lib/dsp/"
fi

# Ensure dynamic linker finds /usr/local/lib/caihong-ssc and /usr/local/lib
cat << 'EOF' > "$ROOTFS/etc/ld.so.conf.d/caihong.conf"
/usr/local/lib
/usr/local/lib/caihong-ssc
/usr/lib
EOF
chroot "$ROOTFS" ldconfig

# CRITICAL FIX 3: Remove Ubuntu's /etc/alsa/state-daemon.conf so alsa-restore uses static VarFile
rm -f "$ROOTFS/etc/alsa/state-daemon.conf"

# CRITICAL FIX 4: Remove Ubuntu's default-wifi-powersave-on.conf and configure systemd-resolved DNS
rm -f "$ROOTFS/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"

# CRITICAL FIX 6: Install UDisks2 ignore rule for Android partitions WITHOUT ENV{SYSTEMD_READY}="0"
cat << 'EOF' > "$ROOTFS/etc/udev/rules.d/80-caihong-android-udisks.rules"
# Hide Android UFS partitions from Dolphin/UDisks2 while keeping systemd device units active for NVRAM MAC reading
SUBSYSTEM=="block", KERNEL=="sd[a-f]*", ENV{ID_PART_ENTRY_NAME}!="linux", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_PRESENTATION_HIDE}="1"
SUBSYSTEM=="block", KERNEL=="dm-*", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_PRESENTATION_HIDE}="1"
SUBSYSTEM=="block", KERNEL=="loop*", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_PRESENTATION_HIDE}="1"
EOF

echo "[5/10] Creating User 'ubuntu' and Adapting KDE Scripts (alarm -> ubuntu)..."
# Create required system groups
for grp in sudo wheel video render audio input bluetooth netdev plugdev adm lp; do
    chroot "$ROOTFS" groupadd -f "$grp"
done

# Create ubuntu user (UID 1000)
if ! chroot "$ROOTFS" id -u ubuntu >/dev/null 2>&1; then
    chroot "$ROOTFS" useradd -m -u 1000 -s /bin/bash -G sudo,wheel,video,render,audio,input,bluetooth,netdev,plugdev,adm ubuntu
fi
echo "ubuntu:ubuntu" | chroot "$ROOTFS" chpasswd
echo "root:root" | chroot "$ROOTFS" chpasswd

# Sudoers configuration
rm -f "$ROOTFS/etc/sudoers.d/10-alarm"
cat << 'EOF' > "$ROOTFS/etc/sudoers.d/90-ubuntu"
ubuntu ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 440 "$ROOTFS/etc/sudoers.d/90-ubuntu"

# Polkit rule so 'Switch to Android' (caihong-slot) and NetworkManager/UDisks2 don't get stuck on modal touch prompts
mkdir -p "$ROOTFS/etc/polkit-1/rules.d"
cat << 'EOF' > "$ROOTFS/etc/polkit-1/rules.d/50-caihong-ubuntu.rules"
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("sudo") || subject.isInGroup("wheel") || subject.user == "ubuntu") {
        return polkit.Result.YES;
    }
});
EOF

# Rewrite 'alarm' -> 'ubuntu' in Caihong KDE & ADB scripts/services, and fix Ubuntu /usr/sbin paths
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

sed -i 's#/usr/bin/resize2fs#/usr/sbin/resize2fs#g' \
    "$ROOTFS/etc/systemd/system/caihong-grow-rootfs.service"
sed -i \
    -e 's#/usr/bin/hostapd#/usr/sbin/hostapd#g' \
    -e 's#/usr/bin/dnsmasq#/usr/sbin/dnsmasq#g' \
    "$ROOTFS/etc/systemd/system/caihong-hotspot.service"

# Remove PowerDevil keyboard brightness plugin in both Qt5 and Qt6 paths (per package-archlinuxarm-rootfs.sh)
rm -f "$ROOTFS/usr/lib/qt6/plugins/powerdevil/action/powerdevil_keyboardbrightnesscontrolaction.so" \
      "$ROOTFS/usr/lib/aarch64-linux-gnu/qt5/plugins/powerdevil/action/powerdevil_keyboardbrightnesscontrolaction.so" 2>/dev/null || true

# Configure persistent regulatory domain at module, boot, udev, and NM levels so ath12k keeps 5GHz active scan
mkdir -p "$ROOTFS/etc/modprobe.d" "$ROOTFS/etc/NetworkManager/dispatcher.d"
cat << 'EOF' > "$ROOTFS/etc/modprobe.d/caihong-wifi.conf"
options cfg80211 ieee80211_regdom=US
EOF
chmod 644 "$ROOTFS/etc/modprobe.d/caihong-wifi.conf"

cat << 'EOF' > "$ROOTFS/usr/local/sbin/caihong-wifi-regdom"
#!/bin/sh
set -u

COUNTRY="${CAIHONG_WIFI_COUNTRY:-US}"

phy_has_country() {
    iw reg get 2>/dev/null | awk -v c="$COUNTRY" '
        /^phy#[0-9]+/ { in_phy = 1; next }
        in_phy && $1 == "country" {
            code = $2
            sub(/:$/, "", code)
            if (code == c) found = 1
            in_phy = 0
        }
        END { exit(found ? 0 : 1) }
    '
}

if [ "${1:-}" = "--wait" ]; then
    i=0
    while [ "$i" -lt 50 ]; do
        for p in /sys/class/ieee80211/phy*; do
            [ -e "$p" ] && break 2
        done
        sleep 0.1
        i=$((i + 1))
    done

    iw reg set "$COUNTRY" >/dev/null 2>&1 || true
    i=0
    while [ "$i" -lt 30 ]; do
        if phy_has_country; then
            exit 0
        fi
        [ "$((i % 5))" -eq 0 ] && iw reg set "$COUNTRY" >/dev/null 2>&1 || true
        sleep 0.1
        i=$((i + 1))
    done
    exit 0
fi

exec iw reg set "$COUNTRY"
EOF
chmod 755 "$ROOTFS/usr/local/sbin/caihong-wifi-regdom"

cat << 'EOF' > "$ROOTFS/etc/systemd/system/caihong-wifi-regdom.service"
[Unit]
Description=Set Caihong Wi-Fi regulatory domain for 5GHz support
DefaultDependencies=no
After=systemd-modules-load.service systemd-udev-settle.service
Before=NetworkManager.service wpa_supplicant.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/caihong-wifi-regdom --wait

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > "$ROOTFS/etc/udev/rules.d/81-caihong-wifi-regdom.rules"
ACTION=="add", SUBSYSTEM=="ieee80211", RUN+="/usr/local/sbin/caihong-wifi-regdom"
EOF
chmod 644 "$ROOTFS/etc/systemd/system/caihong-wifi-regdom.service" "$ROOTFS/etc/udev/rules.d/81-caihong-wifi-regdom.rules"

cat << 'EOF' > "$ROOTFS/etc/NetworkManager/dispatcher.d/10-caihong-wifi-regdom"
#!/bin/sh
case "${2:-}" in
    pre-up|up|connectivity-change)
        if iw reg get 2>/dev/null | grep -q 'country 00:'; then
            /usr/local/sbin/caihong-wifi-regdom >/dev/null 2>&1 || true
        fi
        ;;
esac
exit 0
EOF
chmod 755 "$ROOTFS/etc/NetworkManager/dispatcher.d/10-caihong-wifi-regdom"

echo "[6/10] Configuring KDE Plasma 5.27 Wayland, SDDM, Touch OSK, and 200% Display Scaling..."
# Configure Locale and Timezone
chroot "$ROOTFS" locale-gen en_US.UTF-8 zh_CN.UTF-8
cat << 'EOF' > "$ROOTFS/etc/default/locale"
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh:en_US:en
EOF
ln -sf /usr/share/zoneinfo/Asia/Shanghai "$ROOTFS/etc/localtime"
echo "OnePlus-Pad-Pro" > "$ROOTFS/etc/hostname"
cat << 'EOF' > "$ROOTFS/etc/hosts"
127.0.0.1   localhost
127.0.1.1   OnePlus-Pad-Pro
::1         localhost ip6-localhost ip6-loopback
EOF

# Configure SDDM: Autologin straight into KDE Plasma Wayland with HiDPI and QtVirtualKeyboard fallback
mkdir -p "$ROOTFS/etc/sddm.conf.d"
cat << 'EOF' > "$ROOTFS/etc/sddm.conf.d/caihong-kde.conf"
[Autologin]
User=ubuntu
Session=plasmawayland.desktop
Relogin=false

[General]
InputMethod=qtvirtualkeyboard

[Wayland]
EnableHiDPI=true

[X11]
EnableHiDPI=true
EOF

# Pre-configure KDE Plasma user settings in /home/ubuntu/.config
UBU_CONFIG="$ROOTFS/home/ubuntu/.config"
mkdir -p "$UBU_CONFIG" "$ROOTFS/home/ubuntu/Desktop"

# 1) kwinrc: Enable Maliit Touch On-Screen Keyboard on Wayland, disable tearing, + 200% Xwayland scaling
cat << 'EOF' > "$UBU_CONFIG/kwinrc"
[Compositing]
AllowTearing=false

[Wayland]
InputMethod[$e]=/usr/share/applications/com.github.maliit.keyboard.desktop
VirtualKeyboardEnabled=true

[Xwayland]
Scale=2

[Windows]
BorderlessMaximizedWindows=false
Placement=Centered
EOF

# 1b) Linear 8-bit display workarounds (avoid AR30/UBWC text corruption & WebKit DMABUF flicker) + native Wayland IME
mkdir -p "$ROOTFS/etc/environment.d" "$UBU_CONFIG/environment.d" "$UBU_CONFIG/plasma-workspace/env" "$ROOTFS/etc/systemd/user/plasma-workspace-wayland.target.wants" "$ROOTFS/etc/systemd/user/graphical-session.target.wants"
cat << 'EOF' > "$ROOTFS/etc/environment.d/90-caihong-display.conf"
KWIN_DRM_PREFER_COLOR_DEPTH=24
FD_MESA_DEBUG=noubwc
ELECTRON_OZONE_PLATFORM_HINT=auto
WEBKIT_DISABLE_DMABUF_RENDERER=1
QT_QPA_PLATFORM=wayland;xcb
EOF
cat << 'EOF' > "$UBU_CONFIG/environment.d/10-fcitx5.conf"
XMODIFIERS=@im=fcitx
ELECTRON_OZONE_PLATFORM_HINT=auto
WEBKIT_DISABLE_DMABUF_RENDERER=1
KWIN_DRM_PREFER_COLOR_DEPTH=24
FD_MESA_DEBUG=noubwc
QT_QPA_PLATFORM=wayland;xcb
EOF
cat << 'EOF' > "$UBU_CONFIG/plasma-workspace/env/fcitx5.sh"
#!/bin/sh
unset GTK_IM_MODULE
unset QT_IM_MODULE
export XMODIFIERS=@im=fcitx
export ELECTRON_OZONE_PLATFORM_HINT=auto
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export KWIN_DRM_PREFER_COLOR_DEPTH=24
export FD_MESA_DEBUG=noubwc
export QT_QPA_PLATFORM="wayland;xcb"
EOF
chmod 0644 "$ROOTFS/etc/environment.d/90-caihong-display.conf" "$UBU_CONFIG/environment.d/10-fcitx5.conf" "$UBU_CONFIG/plasma-workspace/env/fcitx5.sh"

for flags_file in chrome-flags.conf code-flags.conf electron-flags.conf antigravity-flags.conf; do
    cat << 'EOF' > "$UBU_CONFIG/$flags_file"
--ozone-platform-hint=auto
--enable-wayland-ime
--wayland-text-input-version=3
EOF
done

# 1c) caihong-im-auto: Switch KWin InputMethod dynamically between Maliit OSK and Fcitx5 on real QWERTY hotplug
cat << 'EOF' > "$ROOTFS/usr/local/bin/caihong-im-auto"
#!/usr/bin/env python3
"""Switch KWin Wayland InputMethod dynamically between Maliit OSK and Fcitx5."""

from pathlib import Path
import subprocess
import sys
import time

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

MALIIT_DESKTOP = "/usr/share/applications/com.github.maliit.keyboard.desktop"
FCITX5_DESKTOP = "/usr/share/applications/fcitx5-wayland-launcher.desktop"
KWINRC = Path.home() / ".config/kwinrc"
QWERTY_MASK = 0x03FF0000  # KEY_Q(16)..KEY_P(25)


def has_real_hardware_keyboard() -> bool:
    for event_dir in sorted(Path("/sys/class/input").glob("event*")):
        dev_node = f"/dev/input/{event_dir.name}"
        try:
            res = subprocess.run(
                ["udevadm", "info", "-q", "property", dev_node],
                capture_output=True, text=True, timeout=2, check=False,
            )
        except OSError:
            continue
        if "ID_INPUT_KEYBOARD=1" not in res.stdout.splitlines():
            continue
        key_caps = event_dir / "device/capabilities/key"
        try:
            words = key_caps.read_text(encoding="utf-8").strip().split()
            if words and (int(words[-1], 16) & QWERTY_MASK) == QWERTY_MASK:
                return True
        except (OSError, ValueError):
            continue
    return False


def current_kwin_im() -> str:
    if not KWINRC.exists():
        return ""
    in_wl = False
    for line in KWINRC.read_text(encoding="utf-8", errors="replace").splitlines():
        s = line.strip()
        if s.startswith("["):
            in_wl = (s == "[Wayland]")
        elif in_wl and s.startswith("InputMethod"):
            return s.split("=", 1)[1].strip()
    return ""


def set_kwin_im(desktop: str, bus: Gio.DBusConnection) -> None:
    if KWINRC.exists():
        lines = KWINRC.read_text(encoding="utf-8", errors="replace").splitlines()
    else:
        KWINRC.parent.mkdir(parents=True, exist_ok=True)
        lines = []

    out = []
    in_wl = False
    wrote = False
    for line in lines:
        s = line.strip()
        if s == "[Wayland]":
            in_wl = True
            out.append(line)
            continue
        if in_wl and s.startswith("["):
            if not wrote:
                out.append(f"InputMethod[$e]={desktop}")
                wrote = True
            in_wl = False
        if in_wl and (s.startswith("InputMethod") or s == "VirtualKeyboardEnabled=false"):
            if s.startswith("InputMethod"):
                if not wrote:
                    out.append(f"InputMethod[$e]={desktop}")
                    wrote = True
                continue
        out.append(line)

    if in_wl and not wrote:
        out.append(f"InputMethod[$e]={desktop}")
        wrote = True
    if not wrote:
        out.extend(["", "[Wayland]", f"InputMethod[$e]={desktop}", "VirtualKeyboardEnabled=true"])

    tmp = KWINRC.with_suffix(".tmp")
    tmp.write_text("\n".join(out) + "\n", encoding="utf-8")
    tmp.replace(KWINRC)

    bus.emit_signal(
        None, "/kwinrc", "org.kde.kconfig.notify", "ConfigChanged",
        GLib.Variant("(a{saay})", ({"Wayland": [list(b"InputMethod"), list(b"VirtualKeyboardEnabled")]},)),
    )
    bus.flush_sync(None)


def wait_for_kwin(bus: Gio.DBusConnection) -> None:
    for _ in range(30):
        try:
            res = bus.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "NameHasOwner",
                GLib.Variant("(s)", ("org.kde.KWin",)),
                GLib.VariantType("(b)"), Gio.DBusCallFlags.NONE, 1000, None,
            ).unpack()
            if res[0]:
                return
        except GLib.Error:
            pass
        time.sleep(0.5)


def sync_once(bus: Gio.DBusConnection, force: bool = False) -> None:
    target = FCITX5_DESKTOP if has_real_hardware_keyboard() else MALIIT_DESKTOP
    if force or current_kwin_im() != target:
        set_kwin_im(target, bus)
        if target == MALIIT_DESKTOP:
            try:
                has_owner = bus.call_sync(
                    "org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "NameHasOwner",
                    GLib.Variant("(s)", ("org.fcitx.Fcitx5",)),
                    GLib.VariantType("(b)"), Gio.DBusCallFlags.NONE, 500, None,
                ).unpack()[0]
                if has_owner:
                    bus.call_sync(
                        "org.fcitx.Fcitx5", "/controller",
                        "org.fcitx.Fcitx.Controller1", "Exit",
                        None, None, Gio.DBusCallFlags.NONE, 500, None,
                    )
            except GLib.Error:
                pass
        print(f"Switched KWin InputMethod -> {target}", flush=True)


def main() -> int:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    wait_for_kwin(bus)
    sync_once(bus, force=True)

    if "--once" in sys.argv:
        return 0

    proc = subprocess.Popen(
        ["udevadm", "monitor", "--udev", "--subsystem-match=input"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    last_check = 0.0
    for line in proc.stdout:
        if "UDEV" not in line:
            continue
        now = time.monotonic()
        if now - last_check < 0.25:
            continue
        time.sleep(0.15)
        last_check = time.monotonic()
        sync_once(bus)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
EOF
chmod 0755 "$ROOTFS/usr/local/bin/caihong-im-auto"

cat << 'EOF' > "$ROOTFS/etc/systemd/user/caihong-im-auto.service"
[Unit]
Description=Auto switch KWin InputMethod between Maliit OSK and Fcitx5
PartOf=graphical-session.target
After=plasma-kwin_wayland.service

[Service]
Type=simple
ExecStart=/usr/local/bin/caihong-im-auto
Restart=on-failure
RestartSec=2

[Install]
WantedBy=plasma-workspace-wayland.target
EOF
chmod 0644 "$ROOTFS/etc/systemd/user/caihong-im-auto.service"
ln -sf ../caihong-im-auto.service "$ROOTFS/etc/systemd/user/plasma-workspace-wayland.target.wants/caihong-im-auto.service"
ln -sf ../caihong-im-auto.service "$ROOTFS/etc/systemd/user/graphical-session.target.wants/caihong-im-auto.service"

# 2) kcminputrc: Touchpad natural scrolling and tap-to-click for OnePlus Smart Keyboard
cat << 'EOF' > "$UBU_CONFIG/kcminputrc"
[Libinput][10462][51332][OnePlus Smart Keyboard]
NaturalScroll=true
TapToClick=true
EOF

# 3) kscreenlockerrc: Disable auto screen lock so tablet never traps touch input
cat << 'EOF' > "$UBU_CONFIG/kscreenlockerrc"
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
EOF

# 4) baloofilerc: Disable background file indexer to prevent I/O spikes
cat << 'EOF' > "$UBU_CONFIG/baloofilerc"
[Basic Settings]
Indexing-Enabled=false
EOF

# 5) powermanagementprofilesrc: Turn off screen on power button press and prevent deep suspend on idle
cat << 'EOF' > "$UBU_CONFIG/powermanagementprofilesrc"
[AC][DPMSControl]
idleTime=600
lockBeforeTurnOff=0

[AC][HandleButtonEvents]
lidAction=1
powerButtonAction=64
powerDownAction=16
triggerLidActionWhenExternalMonitorPresent=false

[Battery][DPMSControl]
idleTime=300
lockBeforeTurnOff=0

[Battery][HandleButtonEvents]
lidAction=1
powerButtonAction=64
powerDownAction=16
triggerLidActionWhenExternalMonitorPresent=false

[LowBattery][DPMSControl]
idleTime=120
lockBeforeTurnOff=0

[LowBattery][HandleButtonEvents]
lidAction=1
powerButtonAction=64
powerDownAction=16
triggerLidActionWhenExternalMonitorPresent=false
EOF

# 5b) kwalletrc & plasma-nm (system-wide /etc/xdg and user): Disable KDE Wallet prompts and store Wi-Fi credentials system-wide in Netplan/NM
cat << 'EOF' > "$ROOTFS/etc/xdg/kwalletrc"
[Wallet]
Enabled=false
First Use=false
EOF

cat << 'EOF' > "$ROOTFS/etc/xdg/plasma-nm"
[General]
SystemConnectionsByDefault=true
EOF
chmod 644 "$ROOTFS/etc/xdg/kwalletrc" "$ROOTFS/etc/xdg/plasma-nm"

cp -f "$ROOTFS/etc/xdg/kwalletrc" "$UBU_CONFIG/kwalletrc"
cp -f "$ROOTFS/etc/xdg/plasma-nm" "$UBU_CONFIG/plasma-nm"
chmod 600 "$UBU_CONFIG/kwalletrc"
chmod 644 "$UBU_CONFIG/plasma-nm"

# 5c) KScreen control files: Allow auto-rotation even when Pogo keyboard detaches/attaches (tablet mode off)
mkdir -p "$ROOTFS/home/ubuntu/.local/share/kscreen/control/configs" "$ROOTFS/home/ubuntu/.local/share/kscreen/control/outputs"
cat << 'EOF' > "$ROOTFS/home/ubuntu/.local/share/kscreen/control/configs/b5350822fc24a835e633b5bf90f2b56d"
{
    "outputs": [
        {
            "autorotate": true,
            "autorotate-tablet-only": false,
            "id": "b5350822fc24a835e633b5bf90f2b56d",
            "metadata": {
                "name": "DSI-1"
            }
        }
    ]
}
EOF
cat << 'EOF' > "$ROOTFS/home/ubuntu/.local/share/kscreen/control/outputs/b5350822fc24a835e633b5bf90f2b56d"
{
    "autorotate": true,
    "autorotate-tablet-only": false,
    "id": "b5350822fc24a835e633b5bf90f2b56d",
    "metadata": {
        "name": "DSI-1"
    }
}
EOF

# 6) First-login KScreen 200% scaling & landscape initialization script for Plasma 5.27 Wayland
cat << 'EOF' > "$ROOTFS/usr/local/bin/caihong-kde-firstboot-scale"
#!/bin/sh
MARKER="$HOME/.config/caihong-kde-scale-done"
if [ -f "$MARKER" ]; then
    exit 0
fi
# Wait briefly for KWin Wayland & KScreen D-Bus backend to register DSI-1
for i in 1 2 3 4 5; do
    if kscreen-doctor -o 2>/dev/null | grep -q "DSI-1"; then
        kscreen-doctor output.DSI-1.scale.2 >/dev/null 2>&1 || true
        touch "$MARKER"
        exit 0
    fi
    sleep 1
done
EOF
chmod 755 "$ROOTFS/usr/local/bin/caihong-kde-firstboot-scale"

mkdir -p "$ROOTFS/etc/xdg/autostart"
cat << 'EOF' > "$ROOTFS/etc/xdg/autostart/caihong-kde-firstboot-scale.desktop"
[Desktop Entry]
Type=Application
Name=Caihong KDE Initial HiDPI Scale
Exec=/usr/local/bin/caihong-kde-firstboot-scale
OnlyShowIn=KDE;
X-KDE-StartupNotify=false
NoDisplay=true
EOF

# Run caihong-fix-kwin-brightness once during build so kwinoutputconfig.json is pre-populated
chroot "$ROOTFS" /usr/local/sbin/caihong-fix-kwin-brightness || true

# Place "Switch to Android" shortcut on the KDE Desktop as well as Application Menu
cp -a "$ROOTFS/usr/share/applications/caihong-switch-to-android.desktop" "$ROOTFS/home/ubuntu/Desktop/"
chmod +x "$ROOTFS/home/ubuntu/Desktop/caihong-switch-to-android.desktop"
chroot "$ROOTFS" chown -R ubuntu:ubuntu /home/ubuntu

echo "[7/10] Configuring fstab, USB ADB Debugging Key, and Systemd Services..."
cat << 'EOF' > "$ROOTFS/etc/fstab"
# <file system>   <mount point>   <type>  <options>                        <dump> <pass>
PARTLABEL=linux   /               ext4    defaults,noatime,errors=remount-ro 0      1
EOF

# Pre-authorize PC's ADB public key (if present) so 'adb shell' works immediately over USB without prompt
mkdir -p "$ROOTFS/data/misc/adb" "$ROOTFS/root/.android" "$ROOTFS/home/ubuntu/.android"
if [ -n "$ADB_PUBKEY" ] && [ -f "$ADB_PUBKEY" ]; then
    cat "$ADB_PUBKEY" > "$ROOTFS/data/misc/adb/adb_keys"
    cat "$ADB_PUBKEY" > "$ROOTFS/home/ubuntu/.android/adb_keys"
    cat "$ADB_PUBKEY" > "$ROOTFS/root/.android/adbkey.pub"
    sed -i 's/\r$//' "$ROOTFS/data/misc/adb/adb_keys" "$ROOTFS/home/ubuntu/.android/adb_keys" "$ROOTFS/root/.android/adbkey.pub"
    chmod 600 "$ROOTFS/data/misc/adb/adb_keys" "$ROOTFS/home/ubuntu/.android/adb_keys" "$ROOTFS/root/.android/adbkey.pub"
    chroot "$ROOTFS" chown -R ubuntu:ubuntu /home/ubuntu/.android
fi

# Fix permissions on systemd unit files so systemd does not complain about executable bits
chmod 644 "$ROOTFS/etc/systemd/system/"*.service "$ROOTFS/etc/systemd/system/"*.timer 2>/dev/null || true

# Enable all required Caihong and KDE services via chroot systemctl
chroot "$ROOTFS" systemctl enable \
    sddm.service \
    NetworkManager.service \
    systemd-resolved.service \
    bluetooth.service \
    upower.service \
    power-profiles-daemon.service \
    udisks2.service \
    rtkit-daemon.service \
    iio-sensor-proxy.service \
    ssh.service \
    caihong-adbd.service \
    caihong-bluetooth-autostart.service \
    caihong-bluetooth-late-autostart.timer \
    caihong-clean-pogo-kde.service \
    caihong-fix-kwin-brightness.service \
    caihong-grow-rootfs.service \
    caihong-hardware-mac.service \
    caihong-keyboard.service \
    caihong-mark-boot-successful.service \
    caihong-pen-autoconnect.timer \
    caihong-pen-charge.timer \
    caihong-pen-pair.timer \
    caihong-ssc.service \
    caihong-wifi-regdom.service

chroot "$ROOTFS" systemctl set-default graphical.target

# Mask services that cause boot delays or suspend issues on tablet
chroot "$ROOTFS" systemctl mask \
    systemd-networkd-wait-online.service \
    NetworkManager-wait-online.service \
    sleep.target suspend.target hibernate.target hybrid-sleep.target

# Run depmod for installed kernel release
for kver in $(ls "$ROOTFS/usr/lib/modules"); do
    chroot "$ROOTFS" depmod -a "$kver"
done

# Remove policy-rc.d
rm -f "$ROOTFS/usr/sbin/policy-rc.d"

# Ensure /etc/resolv.conf is the symlink to systemd-resolved stub
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"

echo "[7.5/10] Installing Caihong Camera ISP (libcamera), Iris VA-API, and Flashlight UX..."
# Ensure camera BPS striping firmware blobs are present
install -d -m 0755 "$ROOTFS/usr/lib/firmware/qcom/sm8650"
for blob in "$WORKSPACE"/caihong-linux-rootfs/firmware/qcom/sm8650/bps-striping-*.bin; do
    [ -e "$blob" ] || continue
    install -m 0644 "$blob" "$ROOTFS/usr/lib/firmware/qcom/sm8650/"
done

# Unpack prebuilt Osilvfe/libcamera (0.7.2+caihong with BPS striping firmware filter)
if [ -f "$WORKSPACE/deploy/packages/caihong-libcamera-ubuntu24-arm64.tar.gz" ]; then
    tar --no-same-owner -xzpf "$WORKSPACE/deploy/packages/caihong-libcamera-ubuntu24-arm64.tar.gz" -C "$ROOTFS"
    rm -f \
        "$ROOTFS/usr/lib/libcamera/ipa/ipa_soft_simple.so" \
        "$ROOTFS/usr/lib/libcamera/ipa/ipa_soft_simple.so.sign" \
        "$ROOTFS/usr/lib/aarch64-linux-gnu/libcamera/ipa/ipa_soft_simple.so" \
        "$ROOTFS/usr/lib/aarch64-linux-gnu/libcamera/ipa/ipa_soft_simple.so.sign" \
        "$ROOTFS/usr/libexec/libcamera/soft_ipa_proxy" \
        "$ROOTFS/usr/share/libcamera/ipa/simple/sc1320cs.yaml" \
        "$ROOTFS/usr/share/libcamera/ipa/simple/sc820cs.yaml"
fi

# Unpack prebuilt Qualcomm Iris VA-API driver (qcom-va-driver)
if [ -f "$WORKSPACE/deploy/packages/caihong-vaapi-ubuntu24-arm64.tar.gz" ]; then
    tar --no-same-owner -xzpf "$WORKSPACE/deploy/packages/caihong-vaapi-ubuntu24-arm64.tar.gz" -C "$ROOTFS"
fi
chroot "$ROOTFS" ldconfig

# Flashlight CLI in PATH, toggle helper, and Qt6 GUI
if [ -x "$ROOTFS/usr/local/sbin/caihong-flashlight" ]; then
    ln -sf /usr/local/sbin/caihong-flashlight "$ROOTFS/usr/local/bin/caihong-flashlight"
fi
if [ -f "$WORKSPACE/deploy/packages/caihong-flashlight-gui" ]; then
    install -m 0755 "$WORKSPACE/deploy/packages/caihong-flashlight-gui" "$ROOTFS/usr/local/bin/caihong-flashlight-gui"
fi
cat << 'EOF' > "$ROOTFS/usr/local/bin/caihong-flashlight-toggle"
#!/bin/sh
set -eu
if /usr/local/sbin/caihong-flashlight status | grep -q 'led_mode: 2\|brightness=[1-9]'; then
    /usr/local/sbin/caihong-flashlight off
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -i flashlight-off -t 2000 "手电筒" "已关闭" || true
    fi
else
    level=${1:-40}
    /usr/local/sbin/caihong-flashlight on "$level"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -i flashlight-on -t 2000 "手电筒" "已开启 (${level}%)" || true
    fi
fi
EOF
chmod 0755 "$ROOTFS/usr/local/bin/caihong-flashlight-toggle"

cat << 'EOF' > "$ROOTFS/usr/share/applications/caihong-flashlight.desktop"
[Desktop Entry]
Type=Application
Name=手电筒
Name[en]=Flashlight
Comment=控制一加平板 Pro 后置补光灯与亮度
Comment[en]=Control OnePlus Pad Pro rear LED torch and brightness
Exec=/usr/local/bin/caihong-flashlight-gui
Icon=flashlight-on
Terminal=false
Categories=Utility;HardwareSettings;
Keywords=flashlight;torch;led;手电筒;
StartupNotify=true
EOF
chmod 0644 "$ROOTFS/usr/share/applications/caihong-flashlight.desktop"

cat << 'EOF' > "$ROOTFS/usr/share/applications/caihong-camera.desktop"
[Desktop Entry]
Type=Application
Name=相机
Name[en]=Camera
Comment=使用 SM8650 硬件 ISP 打开前后摄像头预览与拍照
Comment[en]=Open front and rear cameras using SM8650 hardware ISP
Exec=/usr/bin/qcam -r gles
Icon=camera-photo
Terminal=false
Categories=AudioVideo;Video;Photography;
Keywords=camera;photo;qcam;libcamera;相机;摄像头;
StartupNotify=true
EOF
chmod 0644 "$ROOTFS/usr/share/applications/caihong-camera.desktop"

install -d -m 0755 "$ROOTFS/home/ubuntu/Desktop"
install -m 0755 "$ROOTFS/usr/share/applications/caihong-flashlight.desktop" "$ROOTFS/home/ubuntu/Desktop/caihong-flashlight.desktop"
install -m 0755 "$ROOTFS/usr/share/applications/caihong-camera.desktop" "$ROOTFS/home/ubuntu/Desktop/caihong-camera.desktop"
chroot "$ROOTFS" chown ubuntu:ubuntu /home/ubuntu/Desktop/caihong-flashlight.desktop /home/ubuntu/Desktop/caihong-camera.desktop

install -d -m 0755 "$ROOTFS/usr/share/caihong"
cat << 'EOF' > "$ROOTFS/usr/share/caihong/libcamera-build-info"
build=caihong
version=0.7.2+caihong
pipelines=simple
isp_backend=qcom-camera-icp-bps
isp_output=nv12
bps_striping_filter=enabled
camera_flash=dual-v4l2
gstreamer=enabled
qcam=enabled
EOF
cat << 'EOF' > "$ROOTFS/usr/share/caihong/vaapi-build-info"
build=caihong
driver=qcom-va-drive
gpu_copy=enabled
cdsp_vpp=disabled
vulkan_vpp=disabled
EOF
chmod 0644 "$ROOTFS/usr/share/caihong/libcamera-build-info" "$ROOTFS/usr/share/caihong/vaapi-build-info"

echo "[8/10] Running Pre-Pack Cleanups..."
# Unmount chroot virtual filesystems before packing
umount -lf "$ROOTFS/dev/pts"
umount -lf "$ROOTFS/dev"
umount -lf "$ROOTFS/sys"
umount -lf "$ROOTFS/proc"

# Ensure /run and /tmp are completely empty so tmpfs mounts cleanly at boot, and reset machine-id
rm -rf "$ROOTFS/run/"* "$ROOTFS/tmp/"* "$ROOTFS/var/crash/"* 2>/dev/null || true
: > "$ROOTFS/etc/machine-id"

echo "[9/10] Packing ext4 Raw Image and Metadata-Hardened Sparse Image..."
rm -f "$RAW_IMG" "$SPARSE_IMG"
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
img2simg "$RAW_IMG" "$SPARSE_IMG"
python3 "$WORKSPACE/scripts/fix_sparse_zero_metadata.py" "$RAW_IMG" "$SPARSE_IMG"
sync

echo "[10/10] Build Complete!"
ls -lh "$RAW_IMG" "$SPARSE_IMG"
