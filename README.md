# OnePlus Pad Pro (caihong) Android + Ubuntu 24.04 Dual Boot

一加平板 Pro（`OPD2404` / 代号 `caihong`，Qualcomm SM8650）的 **ColorOS Android（Slot A）+ Ubuntu 24.04 LTS ARM64 KDE Plasma Wayland（Slot B）** 裸机双系统构建、内核补丁与切换工具套件。

---

## 目录结构

```text
├── android_switcher/              # Android 端双系统一键切换 App（Jetpack Compose + JNI qbootctl）
│   ├── app/src/main/cpp/          # 基于 qbootctl 的 UFS BSG A/B 槽位控制实现
│   └── build_qbootctl.ps1         # Android NDK 编译 libqbootctl.so 脚本
├── deploy/                        # 部署文档、Fastboot 刷写与切槽脚本及轻量级辅助产物
│   ├── 00_repartition_guide.md    # UFS 无损缩容 userdata 并划分 linux 分区指南
│   ├── 02_flash_ubuntu_dualboot.bat
│   ├── switch_to_android.bat
│   ├── switch_to_ubuntu.bat
│   ├── CaihongSwitcher.apk        # 预编译 Android 切换器安装包
│   ├── vbmeta_disabled_b.img      # Slot B 禁用 AVB 校验镜像
│   ├── tools/qbootctl             # 预编译 ARM64 槽位控制工具
│   └── packages/                  # 预编译 libcamera / Iris VA-API / Qt6 手电筒 GUI
└── scripts/                       # 内核构建、补丁、RootFS 构建与校验脚本
    ├── build_kernel_snapd.sh      # 主线 Linux 7.3 内核 + DTB + boot 镜像构建脚本
    ├── build_ubuntu24_kde_clean.sh# 纯净 KDE Plasma Wayland Ubuntu 24.04 RootFS 构建脚本
    ├── fast_pack_and_verify.sh    # 快速叠加校验与 Sparse ext4 打包
    ├── verify_ubuntu_kde_rootfs.sh# RootFS 与 sparse 元数据块一致性检验
    ├── verify_and_sync_kernel.sh  # 校验 boot 镜像并同步内核模块
    ├── caihong_flashlight_gui/    # Qt6 手电筒控制界面源码 (main.cpp)
    ├── rootfs_overlay/            # 覆盖到 rootfs 的定制脚本（如 caihong-flashlight）
    └── patches/                   # 内核与平台关键修复补丁
```

---

## 核心特性与已修复问题

- **存储与 A/B 双槽独立共存**：Slot A 保留原版 ColorOS，Slot B 写入主线 Linux 内核（`boot_b` 并清空 `dtbo_b`），挂载 UFS 末尾独立 `linux` 分区（`root=PARTLABEL=linux`），配合 [fix_sparse_zero_metadata.py](scripts/fix_sparse_zero_metadata.py) 确保 Sparse 镜像中 ext4 元数据块均采用 RAW chunk，兼容高通/一加 Fastboot 刷写。
- **高刷显示与去花屏/防闪屏**：
  - [patch_nt36532_144hz.py](scripts/patch_nt36532_144hz.py) 启用 CSOT NT36532 144Hz 模式及时钟切换支持；
  - 默认配置 `KWIN_DRM_PREFER_COLOR_DEPTH=24`、`FD_MESA_DEBUG=noubwc` 与 `AllowTearing=false`（输出线性 `AR24` 8-bit 帧缓冲），以及 `WEBKIT_DISABLE_DMABUF_RENDERER=1`、`QT_QPA_PLATFORM=wayland;xcb` 和 Electron/Chromium 原生 Wayland 参数，解决 10-bit/UBWC 与 Xwayland 缩放引发的文字花屏和部分窗口闪烁。
- **手电筒硬件修复**：
  - [leds-qcom-flash-pm8550-torch-ires.patch](scripts/patches/leds-qcom-flash-pm8550-torch-ires.patch) 修正 PM8550 4CH 闪光灯控制器 Torch 模式步进电流（由 5mA 调整为 12.5mA/step，消除 `0xee10=0x49` 故障）；
  - [caihong-flashlight-sysfs-first.patch](scripts/patches/caihong-flashlight-sysfs-first.patch) 优先使用 `yellow:flash-0` sysfs 接口，跳过未焊接的开路 `white:flash` 通道，并避免探测无关 V4L2 subdev 造成 ioctl 阻塞；配套 [Qt6 手电筒 GUI](scripts/caihong_flashlight_gui/main.cpp)。
- **输入法与虚拟键盘热插拔自动切换**：
  - [oneplus-pogo-dynamic-input.patch](scripts/patches/oneplus-pogo-dynamic-input.patch) 分离常驻的 `OnePlus Pogo Tablet Mode Switch`（`SW_TABLET_MODE`），仅在磁吸键盘实际连接时动态注册键盘/触控板设备；
  - RootFS 集成 `caihong-im-auto` 用户态监听服务：平板无实体键盘模式自动切换 KWin 至 Maliit 中文拼音虚拟键盘（触控输入栏自动弹出），接入 Pogo/USB/蓝牙实体 QWERTY 键盘后自动热切至 `fcitx5-wayland-launcher` 拼音并统一应用端 Wayland `text-input-v3`。
- **硬件外设与双系统切换**：
  - 集成相机硬件 ISP 补丁（[libcamera-bps-striping-filter.patch](scripts/patches/libcamera-bps-striping-filter.patch)）与高通 Iris VA-API 驱动、BlueZ `btmgmt` FIFO MAC 同步修复（[patch_hardware_mac_btmgmt.py](scripts/patch_hardware_mac_btmgmt.py)）。
  - Android 端提供 [CaihongSwitcher](android_switcher)（Jetpack Compose + `libqbootctl.so`）一键切换回 Ubuntu；Ubuntu 端可通过 `sudo caihong-slot android --reboot` 或桌面快捷方式切回 Android。

---

## 快速开始

### 1. 分区与刷写

大体积系统镜像（`caihong-boot-linux.img`、`caihong-ubuntu24-rootfs.ext4.sparse.img` 及官方基础包/固件）未直接提交到 Git，需按需构建或自行准备。具体步骤参见：
- 分区指南：[deploy/00_repartition_guide.md](deploy/00_repartition_guide.md)
- 部署说明：[deploy/README.md](deploy/README.md)

### 2. 从源码拉取上游依赖与构建（WSL2 / Ubuntu Linux）

1. 克隆上游参考仓库与内核源码：
   ```bash
   git clone https://github.com/Osilvfe/caihong-linux-rootfs.git
   bash scripts/clone_and_inspect_kernel.sh
   ```
2. 下载官方基础资源（`ubuntu-base-24.04.5-base-arm64.tar.gz`、`caihong-platform-assets.tar.zst` 等）：
   ```bash
   python3 scripts/download_assets.py
   ```
3. 编译内核与模块并生成 `deploy/boot/caihong-boot-linux.img`：
   ```bash
   bash scripts/build_kernel_snapd.sh
   ```
4. 构建 Ubuntu 24.04 KDE Plasma Wayland RootFS 并打包为 Sparse ext4：
   ```bash
   sudo ARCH_RAW=/path/to/arch.raw.img bash scripts/build_ubuntu24_kde_clean.sh
   ```
   可用 `ADB_PUBKEY=/path/to/adbkey.pub` 注入调试公钥（默认读取 `$HOME/.android/adbkey.pub`）。

### 3. 构建 Android 切换器（可选）

```powershell
cd android_switcher
.\build_qbootctl.ps1
.\gradlew.bat assembleRelease
```

---

## 致谢

- 上游内核与设备树 / 平台脚本基础：[Osilvfe/caihong-linux-rootfs](https://github.com/Osilvfe/caihong-linux-rootfs) 与 `Osilvfe/linux` (`caihong-v7.3`)
- A/B 槽位 UFS 控制代码参考：`qbootctl`
