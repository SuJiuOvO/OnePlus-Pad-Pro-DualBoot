# 从零构建指南（Kernel / Ubuntu RootFS / Android App）

本文档面向希望**自行编译内核、重构 Ubuntu 24.04 KDE 镜像或修改系统脚本**的开发者，详细说明构建环境准备、各脚本之间的前后依赖关系与可配置环境变量。

> 如仅需直接部署刷机，请优先阅读 [deploy/README.md](../deploy/README.md) 与 [deploy/00_repartition_guide.md](../deploy/00_repartition_guide.md)。

---

## 一、 构建主机环境要求

推荐使用 **WSL2（Ubuntu 24.04 x86_64）** 或原生 **Ubuntu 24.04 Linux x86_64** 主机执行以下构建步骤：

```bash
sudo apt-get update
sudo apt-get install -y \
  bc bison build-essential cpio flex git kmod libelf-dev libssl-dev \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  qemu-user-static binfmt-support debootstrap rsync zstd xz-utils \
  e2fsprogs dosfstools parted android-sdk-libsparse-utils \
  python3 curl wget
```

> 说明：由于构建阶段会在 x86_64 主机上通过 `chroot` 执行 ARM64 二进制命令，需确保 `qemu-aarch64-static` 与内核 `binfmt_misc` 注册已启用；WSL2 下若遇到 `chroot` 无法执行 ARM64 程序，可先运行 `sudo systemctl restart systemd-binfmt` 或检查 `/usr/bin/qemu-aarch64-static`。

---

## 二、 构建数据流总览

```text
1. 上游内核 (Osilvfe/linux:caihong-v7.3)
   + 仓库补丁 (144Hz / PM8550 闪光灯 / Pogo 动态输入)
   ──▶ [build_kernel_snapd.sh] ──▶ deploy/boot/caihong-boot-linux.img + /var/cache/caihong_kernel_build/modules-current

2. 官方 Ubuntu Base ARM64 (24.04.5)
   + 上游平台资源 (caihong-platform-assets.tar.zst / caihong-linux-rootfs)
   + 参考 Arch RootFS (arch.raw.img 中的硬件 daemon/固件/校准数据)
   + 仓库扩展包 (deploy/packages/* + scripts/rootfs_overlay/*)
   ──▶ [build_ubuntu24_kde_clean.sh] ──▶ /var/cache/ubuntu_kde_build (RootFS) + caihong-ubuntu24-rootfs.ext4.sparse.img

3. 后续只改内核或模块时，无需重跑耗时的 apt 安装：
   ──▶ [verify_and_sync_kernel.sh] 同步新模块到 /var/cache/ubuntu_kde_build
   ──▶ [fast_pack_and_verify.sh]   快速重新打包并校验 sparse 镜像
   ──▶ [verify_ubuntu_kde_rootfs.sh] 全项体检
```

---

## 三、 第一阶段：准备上游源码与基础资源

在仓库根目录执行（WSL / Linux）：

### 1. 克隆上游平台仓库与内核源码

```bash
# 1) 克隆 Caihong 平台资产、脚本与固件仓库（包含 verify-caihong-release.py 与 firmware/）
git clone https://github.com/Osilvfe/caihong-linux-rootfs.git

# 2) 拉取主线 7.3 内核源码与 mkbootimg 工具到 /var/cache/caihong_kernel_build
bash scripts/clone_and_inspect_kernel.sh
```

> 所有大体积中间缓存（约数 GB）默认放在 `/var/cache/`，避免污染仓库目录。

### 2. 下载预置引导包、模块与 Ubuntu Base

```bash
# 下载上游 v0.2 boot 镜像、模块包与 caihong-platform-assets.tar.zst 到 deploy/boot/
python3 scripts/download_assets.py

# 查看可用的 Ubuntu 24.04 Base ARM64 下载链接并保存到 deploy/rootfs/ubuntu-base-24.04.5-base-arm64.tar.gz
python3 scripts/find_ubuntu.py
```

同时需要准备一份上游已提取好硬件底层文件的 **Arch Linux ARM 参考镜像 `arch.raw.img`**（`build_ubuntu24_kde_clean.sh` 会从中只读提取 `caihong-adbd`、`caihong-npu`、`libQnnHtp`、`/var/lib/caihong-ssc` 传感器配置与高通固件/服务模板）：

```bash
# 下载上游 Arch sparse 分片并合并解压为稀疏镜像（默认落盘到 /var/cache/arch_rootfs/）
bash scripts/download_arch_rootfs.sh

# 将稀疏镜像还原为 raw ext4 镜像，供后续只读 loop 挂载
simg2img /var/cache/arch_rootfs/caihong-arch-rootfs.ext4.sparse.img /var/cache/arch.raw.img
```

---

## 四、 第二阶段：编译主线内核与打包 `boot.img`

```bash
bash scripts/build_kernel_snapd.sh
```

该脚本会按顺序执行以下动作：
1. 校验 `caihong-linux-rootfs/firmware/SHA256SUMS`。
2. 幂等应用三项本仓库内核修复：
   - `scripts/patch_nt36532_144hz.py`：为 CSOT NT36532 屏幕增加 144Hz 模式及非无缝时钟切换判断。
   - `scripts/patches/leds-qcom-flash-pm8550-torch-ires.patch`：将 PM8550 4CH（`v0p1`）的 Torch 步进电流修正为 `12.5mA/step`（匹配 Android DTBO，消除写亮度报 `0x49` 故障）。
   - `scripts/patches/oneplus-pogo-dynamic-input.patch`：分离独立 Switch 设备 `OnePlus Pogo Tablet Mode Switch`（`SW_TABLET_MODE`），仅在磁吸键盘真正连接时才注册键盘/触控板节点，使 KDE 平板模式准确触发。
3. 使用 `caihong_defconfig` 并开启 `CONFIG_SQUASHFS`（XZ/LZ4/LZO/XATTR 等）编译 `Image`、模块和 `sm8650-oneplus-caihong.dtb`。
4. 安装模块到 `/var/cache/caihong_kernel_build/modules-current`，用 `mkbootimg` 生成 Android Boot v2 镜像，运行上游 `verify-caihong-release.py` 与 `scripts/check_boot_cfg.py`，输出至 `deploy/boot/caihong-boot-linux.img`。

> 若你后续修改了内核并只想重新校验与同步模块到 Ubuntu 构建目录：运行 `sudo bash scripts/verify_and_sync_kernel.sh`。

---

## 五、 第三阶段：构建 Ubuntu 24.04 KDE RootFS 镜像

> 建议顺序：先执行一次完整构建生成 `/var/cache/ubuntu_kde_build`，随后执行 `verify_and_sync_kernel.sh` + `fast_pack_and_verify.sh`，把第二阶段新编译的含补丁内核模块同步进 RootFS 并重新打包。

```bash
# 1) 首次全量构建 RootFS（若 ADB 公钥不在 $HOME/.android/adbkey.pub，可通过 ADB_PUBKEY 指定）
sudo ARCH_RAW=/var/cache/arch.raw.img \
     ADB_PUBKEY=/mnt/c/Users/<你的用户名>/.android/adbkey.pub \
     bash scripts/build_ubuntu24_kde_clean.sh

# 2) 将第二阶段编译的含补丁内核模块 (/var/cache/caihong_kernel_build/modules-current) 同步到 RootFS 缓存
sudo bash scripts/verify_and_sync_kernel.sh

# 3) 增量打包 RootFS 为 sparse 镜像并通过 verify_ubuntu_kde_rootfs.sh 全项校验
sudo ARCH_RAW=/var/cache/arch.raw.img bash scripts/fast_pack_and_verify.sh
```

`build_ubuntu24_kde_clean.sh` 内部共分 10 步，关键处理包括：
- **基础与桌面环境**：解压 `ubuntu-base-24.04.5-base-arm64.tar.gz`，配置清华/阿里云 `ubuntu-ports` 软件源，安装纯净 KDE Plasma 5.27 Wayland（`kwin-wayland`、`sddm`、`maliit-keyboard`、`fcitx5`、`fcitx5-chinese-addons`、`pipewire`、`network-manager`、`bluez` 等）。
- **移植并适配高通/一加平台服务**：
  - 注入 `/var/lib/caihong-ssc`（防止 `hexagonrpcd`/ADSP 崩溃）及 `qcom_drv_video.so`（Iris VA-API）。
  - 用 `scripts/patch_hardware_mac_btmgmt.py` 为 BlueZ 5.72 的 `btmgmt` 注入 FIFO stdin 包装器，防止其在 `systemd` 无终端环境下无限挂起。
  - 配置 `80-caihong-android-udisks.rules` 隐藏桌面文件管理器中的 Android 分区，但不设 `SYSTEMD_READY=0`，避免阻断 MAC NVRAM 读取。
  - 配置 `caihong-wifi-regdom`（保持 5GHz 主动扫描）与电源键息屏/防误锁屏策略。
- **体验问题专项修复**：
  - 写入 `/etc/environment.d/90-caihong-display.conf`、用户环境变量与 `kwinrc`：`KWIN_DRM_PREFER_COLOR_DEPTH=24`、`FD_MESA_DEBUG=noubwc`、`AllowTearing=false`、`WEBKIT_DISABLE_DMABUF_RENDERER=1`、`QT_QPA_PLATFORM=wayland;xcb` 及 Chromium/Electron `--enable-wayland-ime --wayland-text-input-version=3` 参数，根治花屏与部分应用闪屏。
  - 植入 `/usr/local/bin/caihong-im-auto` 及用户态 `systemd` 服务：监测实际具备 QWERTY 键码（`0x03FF0000`）的外接/Pogo 键盘，无实体键盘时切向 `maliit-keyboard` 中文拼音虚拟键盘并退出 `fcitx5`；接上实体键盘时自动热切换至 `fcitx5-wayland-launcher`。
  - 叠加 `scripts/rootfs_overlay/usr/local/sbin/caihong-flashlight`，并安装 `deploy/packages/` 下的 `libcamera`、`VA-API` 与 `caihong-flashlight-gui`。
- **稀疏镜像元数据加固**：调用 `scripts/fix_sparse_zero_metadata.py` 将 sparse 镜像内所有涉及 ext4 元数据块（superblock / GDT / bitmap / inode table / journal）的 `FILL(0)` 与 `DONT_CARE` chunk 强制改写为 `CHUNK_RAW`，防止高通/一加 Fastboot 刷机忽略擦除零块导致开机进 `emergency_ro`。

### 快速重打包与镜像体检

如只调整了系统脚本或叠加层配置（`/var/cache/ubuntu_kde_build` 已存在），无需重新 `apt-get install`，直接运行：

```bash
sudo ARCH_RAW=/var/cache/arch.raw.img bash scripts/fast_pack_and_verify.sh
```

它会同步最新覆盖文件、打包 raw/sparse 镜像并自动调用 `scripts/verify_ubuntu_kde_rootfs.sh` 检查所有服务、依赖库、`ldd`、CRLF 行尾和 sparse 元数据块完整性。

---

## 六、 第四阶段：编译辅助工具（可选）

### 1. Android 切系统工具（`android_switcher/`）

见 [android_switcher/README.md](../android_switcher/README.md)。

### 2. Qt6 手电筒桌面控制界面（`scripts/caihong_flashlight_gui/`）

在平板或 ARM64 chroot 中使用 Qt6（`qt6-base-dev`）编译 `scripts/caihong_flashlight_gui/main.cpp`，输出二进制放到 `/usr/local/bin/caihong-flashlight-gui`（或打包进 `deploy/packages/caihong-flashlight-gui`）：

```bash
g++ -O2 -std=c++17 -fPIC scripts/caihong_flashlight_gui/main.cpp \
  $(pkg-config --cflags --libs Qt6Widgets) -o deploy/packages/caihong-flashlight-gui
```

---

## 七、 补丁清单说明（`scripts/patches/`）

| 补丁文件 | 作用目标 | 解决的问题 |
| :--- | :--- | :--- |
| `leds-qcom-flash-pm8550-torch-ires.patch` | 内核 `drivers/leds/flash/leds-qcom-flash.c` | PM8550 4CH `v0p1` Torch 模式改用 12.5mA/step，消除过流/硬件故障标志 `0x49` |
| `oneplus-pogo-dynamic-input.patch` | 内核 `drivers/input/keyboard/oneplus_pogo.c` | 分离 `SW_TABLET_MODE` 开关，未连接磁吸键盘时不生成虚拟 Keyboard/Touchpad |
| `caihong-flashlight-sysfs-first.patch` | `caihong-linux-rootfs` 内 `caihong-flashlight` | 优先通过 `yellow:flash-0` sysfs 控制，跳过开路 `white:flash` 并防 V4L2 卡死 |
| `libcamera-bps-striping-filter.patch` | `libcamera` (`simple.cpp`) | 检查 SM8650 `bps-striping-*.bin` 固件是否存在，避免无固件分辨率输出异常 |
