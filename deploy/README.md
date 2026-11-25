# OnePlus Pad Pro (caihong) 双系统部署工具包 (Dual Boot Suite)

本套件用于在一加平板 Pro（骁龙 8 Gen 3 / SM8650，代号 `caihong`）上实现 **原版 Android (ColorOS) + Ubuntu 24.04 ARM64 (Mainline Linux)** 裸机双系统。

---

## 目录结构

* **`boot/`**
  * `caihong-boot-linux.img`：专为一加平板 Pro 编译的主线 Linux 6.x 内核与原生设备树（Dual-DSI 3K 144Hz 显示屏、Novatek 触控、FastConnect 7800 Wi-Fi/BT、Adreno 750 GPU 加速），配置为直接挂载 `root=PARTLABEL=linux`。
  * `linux-caihong-modules.pkg.tar.zst`：内核配套模块包（含 UFS 4.0 MCQ 多硬件队列配置）。
  * `caihong-platform-assets.tar.zst`：高通外设固件及校准文件（ath12k、awinic 音频校准、novatek 触控微码）。
* **`rootfs/`**
  * `ubuntu-base-24.04.5-base-arm64.tar.gz`：Canonical 官方 Ubuntu 24.04 LTS ARM64 基础镜像。
  * `caihong-ubuntu24-rootfs.ext4`：装载完毕的一加专属 Ubuntu 24.04 根文件系统。
  * `caihong-ubuntu24-rootfs.ext4.sparse.img`：Android Sparse 格式，用于 fastboot 直接极速写入 `linux` 分区。
* **`00_repartition_guide.md`**：内置 UFS 存储无损缩容与划分 `linux` 分区操作指南。
* **`02_flash_ubuntu_dualboot.bat`**：Windows 一键双系统刷写脚本（将内核写入 `boot_b`，根系统写入 `linux` 分区，并设为默认启动）。
* **`switch_to_android.bat`**：快速切换启动槽位到 Slot A（返回 Android）。
* **`switch_to_ubuntu.bat`**：快速切换启动槽位到 Slot B（进入 Ubuntu 24.04）。

---

## 预设用户信息

* **默认普通用户**：`ubuntu`（密码：`ubuntu`，具备完整 sudo 权限）
* **系统管理员用户**：`root`（密码：`root`）
* **主机名**：`caihong-ubuntu`
