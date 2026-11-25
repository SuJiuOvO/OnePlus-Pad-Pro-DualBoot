package com.caihong.switcher.data

import android.content.Context
import java.io.File

class SlotManager(
    context: Context,
    private val statsReader: DeviceStatsReader,
) {
    private val nativeLibDir = context.applicationInfo.nativeLibraryDir
    private val qbootctlBin = File(nativeLibDir, "libqbootctl.so")

    suspend fun inspect(): Pair<BootState, Long?> {
        val propSlot = statsReader.readCurrentSlotProp()

        val idRes = RootShell.runRoot("id -u")
        if (!idRes.isSuccess || idRes.stdout.trim() != "0") {
            val detail = idRes.stderr.trim().ifEmpty { "需要在 Magisk / KernelSU 中授予 Root 权限" }
            return BootState(
                currentSlot = propSlot,
                nextBootSlot = propSlot,
                rootAvailable = false,
                rootDetail = "未获取 Root",
                backendLabel = "只读模式",
                lastError = detail,
            ) to null
        }

        val qbootPath = qbootctlBin.takeIf { it.exists() }?.absolutePath
        val dumpRes = if (qbootPath != null) {
            RootShell.runRoot(RootShell.quoteArg(qbootPath))
        } else {
            ShellResult(-1, "", "未找到内置 libqbootctl.so")
        }

        val linuxBytes = probeLinuxPartitionBytes()

        if (dumpRes.isSuccess && dumpRes.stdout.isNotBlank()) {
            val dump = SlotOutputParser.parseDump(dumpRes.stdout)
            val current = propSlot ?: dump.currentSlot
            return BootState(
                currentSlot = current,
                nextBootSlot = dump.activeSlot ?: current,
                slots = dump.slots,
                rootAvailable = true,
                rootDetail = "Root 已就绪",
                backendLabel = "qbootctl",
                lastError = null,
            ) to linuxBytes
        }

        val bootctlCmd = findSystemBootctl()
        if (bootctlCmd != null) {
            val currentRes = RootShell.runRoot("${RootShell.quoteArg(bootctlCmd)} get-current-slot")
            val activeRes = RootShell.runRoot("${RootShell.quoteArg(bootctlCmd)} get-active-boot-slot")
            val current = propSlot ?: SlotId.fromString(currentRes.stdout)
            val active = SlotOutputParser.parseActiveSlotOutput(activeRes.stdout) ?: current
            return BootState(
                currentSlot = current,
                nextBootSlot = active,
                rootAvailable = true,
                rootDetail = "Root 已就绪",
                backendLabel = "bootctl",
                lastError = if (dumpRes.combinedOutput.isNotBlank()) dumpRes.combinedOutput else null,
            ) to linuxBytes
        }

        return BootState(
            currentSlot = propSlot,
            nextBootSlot = propSlot,
            rootAvailable = true,
            rootDetail = "Root 已就绪",
            backendLabel = "qbootctl 异常",
            lastError = dumpRes.combinedOutput.ifEmpty { "无法读取 A/B 槽位信息" },
        ) to linuxBytes
    }

    suspend fun switchSlot(target: SlotId, rebootAfter: Boolean): SwitchOutcome {
        val qbootPath = qbootctlBin.takeIf { it.exists() }?.absolutePath
        val bootctlPath = findSystemBootctl()

        var usedBackend: String? = null
        var switchError = ""

        if (qbootPath != null) {
            val res = RootShell.runRoot("${RootShell.quoteArg(qbootPath)} -s ${target.cliArg}")
            if (res.isSuccess && verifyWithQbootctl(qbootPath, target)) {
                usedBackend = "qbootctl"
            } else {
                switchError = res.combinedOutput
            }
        }

        if (usedBackend == null && bootctlPath != null) {
            val res = RootShell.runRoot("${RootShell.quoteArg(bootctlPath)} set-active-boot-slot ${target.index}")
            if (res.isSuccess && verifyWithBootctl(bootctlPath, target)) {
                usedBackend = "bootctl"
            } else if (switchError.isEmpty()) {
                switchError = res.combinedOutput
            } else {
                switchError = "$switchError\nbootctl: ${res.combinedOutput}"
            }
        }

        if (usedBackend == null) {
            val needsRoot = switchError.contains("denied", ignoreCase = true) ||
                switchError.contains("su", ignoreCase = true)
            return SwitchOutcome.Failure(
                reason = switchError.ifEmpty { "切换槽位失败，请确认设备已获取 Root 权限且支持 A/B 分区" },
                needsRoot = needsRoot,
            )
        }

        RootShell.runRoot("sync")
        if (rebootAfter) {
            val rebootRes = RootShell.runRoot("svc power reboot || setprop sys.powerctl reboot || reboot")
            if (!rebootRes.isSuccess) {
                return SwitchOutcome.Success(
                    targetSlot = target,
                    rebooting = false,
                    detail = "已通过 $usedBackend 将下次启动槽位设为 ${target.suffix}，请手动重启生效 (${rebootRes.combinedOutput})",
                )
            }
        }

        return SwitchOutcome.Success(
            targetSlot = target,
            rebooting = rebootAfter,
            detail = if (rebootAfter) {
                "正在重启并切换到 Linux (${target.suffix})"
            } else {
                "已将下次启动槽位设为 ${target.suffix}，稍后重启即可进入目标系统"
            },
        )
    }

    suspend fun rebootNow(): ShellResult {
        RootShell.runRoot("sync")
        return RootShell.runRoot("svc power reboot || setprop sys.powerctl reboot || reboot")
    }

    private suspend fun verifyWithQbootctl(qbootPath: String, target: SlotId): Boolean {
        val verify = RootShell.runRoot("${RootShell.quoteArg(qbootPath)} -a")
        return verify.isSuccess && SlotOutputParser.parseActiveSlotOutput(verify.stdout) == target
    }

    private suspend fun verifyWithBootctl(bootctlPath: String, target: SlotId): Boolean {
        val verify = RootShell.runRoot("${RootShell.quoteArg(bootctlPath)} get-active-boot-slot")
        return verify.isSuccess && SlotOutputParser.parseActiveSlotOutput(verify.stdout) == target
    }

    private suspend fun findSystemBootctl(): String? {
        val check = RootShell.runRoot(
            "for p in /system/bin/bootctl /vendor/bin/bootctl /system_ext/bin/bootctl; do " +
                "if [ -x \"\$p\" ]; then echo \"\$p\"; break; fi; done",
        )
        return check.stdout.trim().takeIf { check.isSuccess && it.startsWith("/") }
    }

    private suspend fun probeLinuxPartitionBytes(): Long? {
        val res = RootShell.runRoot(
            "for p in /dev/block/bootdevice/by-name/linux /dev/block/by-name/linux; do " +
                "if [ -e \"\$p\" ]; then blockdev --getsize64 \"\$p\" 2>/dev/null && break; fi; done",
        )
        return if (res.isSuccess) res.stdout.trim().lines().firstOrNull()?.toLongOrNull() else null
    }
}
