package com.caihong.switcher.data

import java.util.Locale

enum class SlotId(
    val index: Int,
    val cliArg: String,
    val suffix: String,
    val title: String,
) {
    A(index = 0, cliArg = "a", suffix = "_a", title = "槽位 A"),
    B(index = 1, cliArg = "b", suffix = "_b", title = "槽位 B");

    fun opposite(): SlotId = if (this == A) B else A

    companion object {
        fun fromString(raw: String?): SlotId? {
            val clean = raw?.trim()?.lowercase(Locale.ROOT) ?: return null
            return when {
                clean == "_a" || clean == "a" || clean == "0" -> A
                clean == "_b" || clean == "b" || clean == "1" -> B
                else -> null
            }
        }
    }
}

data class SlotMetadata(
    val slot: SlotId,
    val active: Boolean,
    val successful: Boolean,
    val bootable: Boolean,
)

data class QbootctlDump(
    val currentSlot: SlotId?,
    val slots: Map<SlotId, SlotMetadata>,
) {
    val activeSlot: SlotId?
        get() = slots.values.firstOrNull { it.active }?.slot
}

object SlotOutputParser {
    private val slotHeaderRegex = Regex("""^SLOT\s+(_[ab]):""", RegexOption.IGNORE_CASE)

    /** Parses the output of `qbootctl` (with no arguments). */
    fun parseDump(output: String): QbootctlDump {
        var current: SlotId? = null
        val slots = mutableMapOf<SlotId, SlotMetadata>()
        var blockSlot: SlotId? = null
        var active = false
        var successful = false
        var bootable = false

        fun flushBlock() {
            val target = blockSlot ?: return
            slots[target] = SlotMetadata(
                slot = target,
                active = active,
                successful = successful,
                bootable = bootable,
            )
            blockSlot = null
            active = false
            successful = false
            bootable = false
        }

        for (rawLine in output.lines()) {
            val line = rawLine.trim()
            if (line.startsWith("Current slot:", ignoreCase = true)) {
                current = SlotId.fromString(line.substringAfter(":"))
                continue
            }
            val headerMatch = slotHeaderRegex.matchEntire(line)
            if (headerMatch != null) {
                flushBlock()
                blockSlot = SlotId.fromString(headerMatch.groupValues[1])
                continue
            }
            if (blockSlot != null && ":" in line) {
                val key = line.substringBefore(":").trim().lowercase(Locale.ROOT)
                val value = line.substringAfter(":").trim() == "1"
                when (key) {
                    "active" -> active = value
                    "successful" -> successful = value
                    "bootable" -> bootable = value
                }
            }
        }
        flushBlock()
        return QbootctlDump(currentSlot = current, slots = slots)
    }

    /** Parses output of `qbootctl -a` (e.g. `Active slot: _b`) or numeric `bootctl` output. */
    fun parseActiveSlotOutput(output: String): SlotId? {
        val text = output.trim()
        if (text.isEmpty()) return null
        val afterColon = if (":" in text) text.substringAfterLast(":") else text
        return SlotId.fromString(afterColon)
    }
}

data class DeviceInfo(
    val model: String = "Unknown",
    val deviceCode: String = "caihong",
    val hardware: String = "",
    val androidVersion: String = "",
    val romVersion: String = "",
    val buildDisplay: String = "",
    val securityPatch: String = "",
    val kernelRelease: String = "",
    val uptimeMillis: Long = 0L,
) {
    val kernelShort: String
        get() = kernelRelease.substringBefore("-").ifEmpty { kernelRelease }
}

data class BatteryInfo(
    val percent: Int = 0,
    val statusLabel: String = "未知",
    val pluggedLabel: String = "",
    val isCharging: Boolean = false,
    val temperatureCelsius: Float = 0f,
    val voltageMv: Int = 0,
    val currentMa: Int? = null,
    val powerWatts: Float? = null,
)

data class StorageMemoryInfo(
    val ramTotalBytes: Long = 0L,
    val ramAvailableBytes: Long = 0L,
    val dataTotalBytes: Long = 0L,
    val dataAvailableBytes: Long = 0L,
    val linuxPartitionBytes: Long? = null,
)

data class BootState(
    val currentSlot: SlotId? = null,
    val nextBootSlot: SlotId? = null,
    val slots: Map<SlotId, SlotMetadata> = emptyMap(),
    val rootAvailable: Boolean = false,
    val rootDetail: String = "检查中...",
    val backendLabel: String = "",
    val lastError: String? = null,
) {
    val targetLinuxSlot: SlotId
        get() = currentSlot?.opposite() ?: SlotId.B

    val hasPendingSwitch: Boolean
        get() = currentSlot != null && nextBootSlot != null && nextBootSlot != currentSlot
}

sealed interface SwitchOutcome {
    data class Success(val targetSlot: SlotId, val rebooting: Boolean, val detail: String) : SwitchOutcome
    data class Failure(val reason: String, val needsRoot: Boolean = false) : SwitchOutcome
}

object Formatters {
    fun formatBytes(bytes: Long?): String {
        if (bytes == null || bytes <= 0L) return "未知"
        val kb = 1024.0
        val mb = kb * 1024.0
        val gb = mb * 1024.0
        return when {
            bytes >= gb -> String.format(Locale.US, "%.1f GB", bytes / gb)
            bytes >= mb -> String.format(Locale.US, "%.0f MB", bytes / mb)
            else -> String.format(Locale.US, "%.0f KB", bytes / kb)
        }
    }

    fun formatUptime(uptimeMillis: Long): String {
        val totalSeconds = (uptimeMillis / 1000L).coerceAtLeast(0L)
        val days = totalSeconds / 86400L
        val hours = (totalSeconds % 86400L) / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        return when {
            days > 0 -> "${days}天 ${hours}小时 ${minutes}分"
            hours > 0 -> "${hours}小时 ${minutes}分"
            else -> "${minutes}分钟"
        }
    }
}
