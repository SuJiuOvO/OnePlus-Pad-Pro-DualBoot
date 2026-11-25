# CaihongSwitcher (Android 端双系统切换器)

运行在 **已 Root 的 Android（Slot A / ColorOS）** 上的伴侣应用，用于查看当前 A/B 启动槽位、`linux` 分区容量及电池状态，并实现**一键切换到 Slot B 重启进入 Ubuntu**。

---

## 工作原理

- Android 侧通过 Root 权限（Magisk / KernelSU / APatch）执行内置的原生 UFS BSG / GPT 控制工具 `libqbootctl.so`。
- `libqbootctl.so` 实际是一个由 `app/src/main/cpp/`（`qbootctl.c`、`bootctrl_impl.c`、`gpt-utils.c`、`ufs-bsg.c`）编译出来的 **ARM64 PIE 可执行文件**；命名为 `.so` 放到 `app/src/main/jniLibs/arm64-v8a/libqbootctl.so` 是为了借助 Android `useLegacyPackaging = true` 让系统自动将其解压到应用原生库目录，从而免去额外释放可执行文件的权限问题。
- 当 `qbootctl` 不可用时，会自动回退调用系统自带的 `bootctl`（`set-active-boot-slot`）完成槽位切换与校验，随后调用 `sync` 并重启平板。

---

## 目录说明

- `app/src/main/cpp/`：C/C++ 底层 UFS 槽位读写源码（源自 `qbootctl`）。
- `app/src/main/jniLibs/arm64-v8a/libqbootctl.so`：预编译好的 `libqbootctl.so` 可执行产物。
- `app/src/main/java/com/caihong/switcher/`：
  - `MainActivity.kt`：主界面入口。
  - `ui/SwitcherScreen.kt`：Jetpack Compose UI，展示当前槽位、下次启动槽位、`linux` 分区检测和一键切换重启按钮。
  - `data/SlotManager.kt`：封装 `qbootctl` / `bootctl` 状态查询、槽位切换与回读校验。
  - `data/RootShell.kt`：带 8 秒超时保护的 `su -c` 命令执行器。
  - `data/DeviceStatsReader.kt`：读取设备属性、电池状态等信息。
- `build_qbootctl.ps1`：在 Windows 下调用 Android NDK (`aarch64-linux-android31-clang`) 重新编译并 strip `libqbootctl.so`。

---

## 直接安装或自行编译

### 直接安装（推荐）

仓库根目录 [deploy/CaihongSwitcher.apk](../deploy/CaihongSwitcher.apk) 即为打包好的安装包：

```powershell
adb install deploy\CaihongSwitcher.apk
```

首次打开后请在弹窗中授予 **Root 权限**，即可在 App 内点击切换至 Slot B（Ubuntu）。

### 从源码编译

前置条件：Android SDK（API 35）、Android NDK、JDK 17。

```powershell
cd android_switcher

# 1. （可选）如有改动 C 代码，重新编译 native 工具 libqbootctl.so
.\build_qbootctl.ps1

# 2. 编译 Release APK（若使用本地 Android Studio 可直接 Gradle Sync 构建）
gradle assembleRelease
# 或使用已生成的 Gradle Wrapper 脚本后执行 ./gradlew.bat assembleRelease
```
