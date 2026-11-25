package com.caihong.switcher.data

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.SystemClock
import android.system.Os
import kotlin.math.abs
import kotlin.math.roundToInt

class DeviceStatsReader(private val context: Context) {

    suspend fun readDeviceInfo(): DeviceInfo {
        val socModel = readProp("ro.soc.model").ifEmpty {
            readProp("ro.board.platform").ifEmpty { Build.HARDWARE }
        }
        val marketName = readProp("ro.vendor.oplus.market.name").ifEmpty {
            readProp("ro.product.marketname").ifEmpty { Build.MODEL }
        }
        val oplusRom = readProp("ro.build.version.oplusrom.display")
        val romVersion = if (oplusRom.isNotBlank()) "ColorOS $oplusRom" else ""
        val kernel = try {
            Os.uname().release
        } catch (_: Throwable) {
            System.getProperty("os.version").orEmpty()
        }
        return DeviceInfo(
            model = marketName,
            deviceCode = Build.DEVICE,
            hardware = socModel,
            androidVersion = "Android ${Build.VERSION.RELEASE}",
            romVersion = romVersion,
            buildDisplay = Build.DISPLAY,
            securityPatch = Build.VERSION.SECURITY_PATCH,
            kernelRelease = kernel,
            uptimeMillis = SystemClock.elapsedRealtime(),
        )
    }

    fun readBatteryInfo(): BatteryInfo {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val percent = if (level >= 0 && scale > 0) (level * 100f / scale).roundToInt().coerceIn(0, 100) else 0

        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val statusLabel = when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "充电中"
            BatteryManager.BATTERY_STATUS_FULL -> "已充满"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "放电中"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "未充电"
            else -> "未知"
        }

        val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val pluggedLabel = when {
            (plugged and BatteryManager.BATTERY_PLUGGED_AC) != 0 -> "AC 电源"
            (plugged and BatteryManager.BATTERY_PLUGGED_USB) != 0 -> "USB"
            (plugged and BatteryManager.BATTERY_PLUGGED_WIRELESS) != 0 -> "无线充电"
            else -> "电池供电"
        }

        val tempTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val voltageMv = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0) ?: 0

        val bm = context.getSystemService(BatteryManager::class.java)
        val rawCurrent = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
            ?.takeIf { it != Int.MIN_VALUE && it != 0 }
        // Qualcomm kernels usually expose microamperes in CURRENT_NOW, though some report milliamperes.
        val currentMa = rawCurrent?.let { if (abs(it) > 15_000) it / 1000 else it }
        val watts = if (currentMa != null && voltageMv > 0) {
            abs(voltageMv * currentMa) / 1_000_000f
        } else {
            null
        }

        return BatteryInfo(
            percent = percent,
            statusLabel = statusLabel,
            pluggedLabel = pluggedLabel,
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING,
            temperatureCelsius = tempTenths / 10f,
            voltageMv = voltageMv,
            currentMa = currentMa,
            powerWatts = watts,
        )
    }

    fun readStorageMemory(linuxPartitionBytes: Long?): StorageMemoryInfo {
        val am = context.getSystemService(ActivityManager::class.java)
        val memInfo = ActivityManager.MemoryInfo()
        am?.getMemoryInfo(memInfo)

        val statFs = StatFs(Environment.getDataDirectory().path)
        return StorageMemoryInfo(
            ramTotalBytes = memInfo.totalMem,
            ramAvailableBytes = memInfo.availMem,
            dataTotalBytes = statFs.totalBytes,
            dataAvailableBytes = statFs.availableBytes,
            linuxPartitionBytes = linuxPartitionBytes,
        )
    }

    suspend fun readCurrentSlotProp(): SlotId? {
        val raw = readProp("ro.boot.slot_suffix")
        return SlotId.fromString(raw)
    }

    private suspend fun readProp(name: String): String {
        val res = RootShell.runUser("getprop", name)
        return if (res.isSuccess) res.stdout.trim() else ""
    }
}
