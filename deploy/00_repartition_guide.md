# OnePlus Pad Pro (caihong) 双系统无损分区操作指南

本文档指导如何在已解锁 BL + Root 的一加平板 Pro 上对内置 UFS 闪存划分出 `linux` 分区，实现 **原版 Android (ColorOS) + Ubuntu 24.04 ARM64** 双系统独立共存。

---

## 一、 原理说明

1. **A/B 槽位隔离**：
   * **Slot A**：保留原版 Android 内核（`boot_a`、`init_boot_a`、`dtbo_a`）。
   * **Slot B**：写入 Ubuntu 24.04 主线内核（`boot_b`），擦除 `dtbo_b`。
2. **磁盘空间分配**：
   * 一加平板 Pro 的主存储芯片为 `/dev/block/sda`，末尾分区为 `userdata`（Android 用户数据）。
   * 我们通过 `parted` 工具将 `userdata` 缩容（例如腾出 64GB 空间），在末尾新建一个名为 `linux` 的 ext4 分区。
   * Android 启动时依然挂载 `userdata`；Ubuntu 启动时自动通过设备树参数 `root=PARTLABEL=linux` 挂载 `linux` 分区。

---

## 二、 分区操作步骤（在 Recovery 或 ADB Shell 中执行）

### 1. 进入设备终端
平板开机并连接电脑，确保打开 USB 调试，并在终端中执行：
```sh
adb reboot recovery
# 或在系统开机状态下直接使用 root 权限：
adb shell
su
```

### 2. 启动 parted
```sh
parted /dev/block/sda
```

### 3. 查看当前物理分区表
在 `(parted)` 交互提示符下输入：
```text
unit GB
print
```
找到最后一项（通常是编号最大的一项，名称为 `userdata`）。
记录其：
* **Number（编号）**：例如 `31`
* **Start（起始位置）**：例如 `18.5GB`
* **End（结束位置）**：例如 `256GB`

### 4. 重新划分 userdata 与新建 linux 分区
假设总容量 256GB，起始位置为 `18.5GB`，我们希望留出 64GB 给 Ubuntu，则分界点选在 `192GB`：

```text
rm <userdata编号>
mkpart userdata ext4 <原Start位置> 192GB
mkpart linux ext4 192GB 100%
name <新linux分区编号> linux
print
quit
```

*注意：`rm <编号>` 只是修改 GPT 分区表指针，只要起始扇区完全一致，在部分情况下能保留文件系统，但最稳妥的做法是确保重要数据已备份。*

### 5. 返回 Bootloader 刷写系统
```sh
adb reboot bootloader
```
进入 fastboot 模式后，直接运行部署目录下的 `02_flash_ubuntu_dualboot.bat` 即可一键刷入 Ubuntu 24.04！

---

## 三、 双系统切换方式

1. **在电脑端切换**：
   * 切换回 Android：双击运行 `deploy/switch_to_android.bat`
   * 切换回 Ubuntu：双击运行 `deploy/switch_to_ubuntu.bat`
2. **在 Ubuntu 系统内直接切换回 Android**：
   * 打开终端输入：
     ```bash
     sudo caihong-slot android --reboot
     ```
   * 或在应用菜单中点击 **“切换到 Android”**，平板将自动设置 Slot A 并重启进入 ColorOS。
3. **在 Android 系统内切换回 Ubuntu**：
   * 在已 Root 的 Android 终端（Termux 或 Magisk 终端模拟器）中输入：
     ```bash
     su
     bootctl set-active-boot-slot 1
     reboot
     ```
