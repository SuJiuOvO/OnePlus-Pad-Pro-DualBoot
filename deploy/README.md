# OnePlus Pad Pro (caihong) 双系统部署目录说明

本目录用于存放在一加平板 Pro（骁龙 8 Gen 3 / `OPD2404` / 代号 `caihong`）上实现 **原版 Android (ColorOS, Slot A) + Ubuntu 24.04 LTS ARM64 KDE Plasma Wayland (Slot B)** 双系统刷写所需的脚本、文档与轻量化工具。

---

## 文件与子目录说明

### 仓库内置（可直接获取）

| 路径 | 用途说明 |
| :--- | :--- |
| [00_repartition_guide.md](00_repartition_guide.md) | 内置 UFS 闪存无损缩容 `userdata` 并创建 `linux` 分区的详细图文命令指南 |
| [02_flash_ubuntu_dualboot.bat](02_flash_ubuntu_dualboot.bat) | Windows Fastboot 一键刷写脚本（擦除 `dtbo_b`，刷入 `boot_b` 与 `linux` 分区并激活 Slot B） |
| [switch_to_android.bat](switch_to_android.bat) | Fastboot 模式下将启动槽位切回 Slot A（Android）并重启 |
| [switch_to_ubuntu.bat](switch_to_ubuntu.bat) | Fastboot 模式下将启动槽位切回 Slot B（Ubuntu）并重启 |
| [CaihongSwitcher.apk](CaihongSwitcher.apk) | Android 端双系统切换器（需 Root），用于在 Android 内一键切回 Ubuntu |
| [vbmeta_disabled_b.img](vbmeta_disabled_b.img) | 关闭 Slot B AVB 校验（flags=`0x3`）的 `vbmeta_b` 镜像，仅在设备提示验证失败无法启动时刷入 |
| `tools/qbootctl` | 预编译 ARM64 通用 UFS 槽位控制命令行工具 |
| `packages/` | 预编译 Ubuntu 24.04 适配包（`libcamera` 相机 ISP、Qualcomm Iris `VA-API` 驱动、`caihong-flashlight-gui`） |

### 需本地准备的大体积镜像（因超过 Git 单文件限制，未纳入 Git 跟踪）

在执行 [02_flash_ubuntu_dualboot.bat](02_flash_ubuntu_dualboot.bat) 前，请先按 [../docs/BUILD_FROM_SOURCE.md](../docs/BUILD_FROM_SOURCE.md) 构建（或自行放入）以下文件到对应位置：

* **`boot/caihong-boot-linux.img`**：主线 Linux 7.3 内核与原生设备树镜像（由 `scripts/build_kernel_snapd.sh` 生成，刷入 `boot_b`）。
* **`rootfs/caihong-ubuntu24-rootfs.ext4.sparse.img`**：Android Sparse 格式 Ubuntu 24.04 KDE RootFS 镜像（由 `scripts/build_ubuntu24_kde_clean.sh` 或 `scripts/fast_pack_and_verify.sh` 生成，刷入 `linux` 分区）。
* **（仅构建过程需要）**：
  * `boot/linux-caihong-modules.pkg.tar.zst`、`boot/caihong-platform-assets.tar.zst`（可通过 `python3 scripts/download_assets.py` 拉取）。
  * `rootfs/ubuntu-base-24.04.5-base-arm64.tar.gz`（Canonical 官方 Ubuntu 24.04.5 Base ARM64 基础包）。

---

## 刷机前必须备份原厂分区

强烈建议在动任何分区与槽位前，先在 **Android Root Shell / Recovery** 中导出原厂关键分区备份到电脑，以防误操作或未来还原：

```sh
adb shell "su -c 'dd if=/dev/block/by-name/boot_b of=/sdcard/stock_boot_b.img'"
adb shell "su -c 'dd if=/dev/block/by-name/dtbo_b of=/sdcard/stock_dtbo_b.img'"
adb shell "su -c 'dd if=/dev/block/by-name/vbmeta_a of=/sdcard/stock_vbmeta_a.img'"
adb shell "su -c 'dd if=/dev/block/by-name/vbmeta_b of=/sdcard/stock_vbmeta_b.img'"
adb pull /sdcard/stock_boot_b.img deploy/
adb pull /sdcard/stock_dtbo_b.img deploy/
adb pull /sdcard/stock_vbmeta_a.img deploy/
adb pull /sdcard/stock_vbmeta_b.img deploy/
```

---

## 预设 Ubuntu 系统信息

* **默认普通用户**：`ubuntu`（密码：`ubuntu`，免密 `sudo` 权限）
* **系统管理员用户**：`root`（密码：`root`）
* **主机名**：`OnePlus-Pad-Pro`
* **桌面环境**：KDE Plasma 5.27 Wayland（默认 200% HiDPI 缩放）
* **调试通道**：开机自动开启 SSH（`22` 端口）与 USB ADB（`caihong-adbd`，可预置 PC 公钥实现免确认 `adb shell`）
