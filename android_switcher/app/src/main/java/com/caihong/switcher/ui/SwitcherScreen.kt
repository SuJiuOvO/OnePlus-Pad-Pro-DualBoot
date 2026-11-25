package com.caihong.switcher.ui

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.caihong.switcher.R
import com.caihong.switcher.data.BatteryInfo
import com.caihong.switcher.data.BootState
import com.caihong.switcher.data.DeviceInfo
import com.caihong.switcher.data.Formatters
import com.caihong.switcher.data.SlotId
import com.caihong.switcher.data.SlotMetadata
import com.caihong.switcher.data.StorageMemoryInfo
import com.caihong.switcher.ui.theme.LocalAppPalette
import java.util.Locale
import kotlin.math.abs

data class UiState(
    val bootState: BootState = BootState(),
    val deviceInfo: DeviceInfo = DeviceInfo(),
    val batteryInfo: BatteryInfo = BatteryInfo(),
    val storageMemory: StorageMemoryInfo = StorageMemoryInfo(),
    val isRefreshing: Boolean = false,
    val isSwitching: Boolean = false,
    val bannerMessage: String? = null,
    val bannerIsError: Boolean = false,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwitcherScreen(
    state: UiState,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
    onRefresh: () -> Unit,
    onSwitchToSlot: (SlotId, Boolean) -> Unit,
    onRebootNow: () -> Unit,
    onDismissBanner: () -> Unit,
) {
    val palette = LocalAppPalette.current
    val haptic = LocalHapticFeedback.current
    var pendingConfirmTarget by remember { mutableStateOf<Pair<SlotId, Boolean>?>(null) }
    var showRootSheet by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
        contentAlignment = Alignment.TopCenter,
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .widthIn(max = 940.dp)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 20.dp),
        ) {
            val isLandscapeTablet = maxWidth >= 840.dp
            val isTablet = maxWidth >= 560.dp

            Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                TopHeader(
                    deviceInfo = state.deviceInfo,
                    bootState = state.bootState,
                    isDark = isDark,
                    isRefreshing = state.isRefreshing,
                    onToggleTheme = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onToggleTheme()
                    },
                    onRefresh = onRefresh,
                    onRootBadgeClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        if (!state.bootState.rootAvailable) showRootSheet = true else onRefresh()
                    },
                )

                AnimatedVisibility(visible = state.bannerMessage != null) {
                    state.bannerMessage?.let { msg ->
                        FeedbackBanner(
                            message = msg,
                            isError = state.bannerIsError,
                            onDismiss = onDismissBanner,
                        )
                    }
                }

                SwitchHeroCard(
                    bootState = state.bootState,
                    deviceInfo = state.deviceInfo,
                    linuxPartitionBytes = state.storageMemory.linuxPartitionBytes,
                    isSwitching = state.isSwitching,
                    isWideActions = isTablet,
                    onRequestSwitch = { rebootAfter ->
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        if (!state.bootState.rootAvailable) {
                            showRootSheet = true
                        } else {
                            pendingConfirmTarget = state.bootState.targetLinuxSlot to rebootAfter
                        }
                    },
                    onRevertToCurrent = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        val current = state.bootState.currentSlot ?: return@SwitchHeroCard
                        onSwitchToSlot(current, false)
                    },
                    onRebootNow = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onRebootNow()
                    },
                )

                when {
                    isLandscapeTablet -> {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            BatteryCard(
                                battery = state.batteryInfo,
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight(),
                            )
                            MemoryStorageCard(
                                storage = state.storageMemory,
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight(),
                            )
                            SystemSlotsCard(
                                bootState = state.bootState,
                                device = state.deviceInfo,
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight(),
                            )
                        }
                    }

                    isTablet -> {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            BatteryCard(
                                battery = state.batteryInfo,
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight(),
                            )
                            MemoryStorageCard(
                                storage = state.storageMemory,
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight(),
                            )
                        }
                        SystemSlotsCard(
                            bootState = state.bootState,
                            device = state.deviceInfo,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }

                    else -> {
                        BatteryCard(battery = state.batteryInfo, modifier = Modifier.fillMaxWidth())
                        MemoryStorageCard(storage = state.storageMemory, modifier = Modifier.fillMaxWidth())
                        SystemSlotsCard(
                            bootState = state.bootState,
                            device = state.deviceInfo,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                Spacer(modifier = Modifier.height(6.dp))
            }
        }
    }

    pendingConfirmTarget?.let { (targetSlot, shouldReboot) ->
        ModalBottomSheet(
            onDismissRequest = { pendingConfirmTarget = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = palette.card,
            contentColor = palette.textPrimary,
            shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        ) {
            ConfirmSwitchSheetContent(
                currentSlot = state.bootState.currentSlot,
                targetSlot = targetSlot,
                rebootAfter = shouldReboot,
                onCancel = { pendingConfirmTarget = null },
                onConfirm = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    pendingConfirmTarget = null
                    onSwitchToSlot(targetSlot, shouldReboot)
                },
            )
        }
    }

    if (showRootSheet) {
        ModalBottomSheet(
            onDismissRequest = { showRootSheet = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = palette.card,
            contentColor = palette.textPrimary,
            shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        ) {
            RootHelpSheetContent(
                errorDetail = state.bootState.lastError,
                onDismiss = { showRootSheet = false },
                onRetry = {
                    showRootSheet = false
                    onRefresh()
                },
            )
        }
    }
}

@Composable
private fun TopHeader(
    deviceInfo: DeviceInfo,
    bootState: BootState,
    isDark: Boolean,
    isRefreshing: Boolean,
    onToggleTheme: () -> Unit,
    onRefresh: () -> Unit,
    onRootBadgeClick: () -> Unit,
) {
    val palette = LocalAppPalette.current

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "双系统切换",
                color = palette.textPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-0.5).sp,
            )
            val subtitle = listOf(deviceInfo.model, deviceInfo.hardware)
                .filter { it.isNotBlank() }
                .joinToString(" · ")
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    color = palette.textSecondary,
                    fontSize = 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val dotColor = if (bootState.rootAvailable) palette.androidAccent else palette.amberAccent
            val badgeText = if (bootState.rootAvailable) "已授 Root" else "未授 Root"

            Surface(
                color = palette.card,
                shape = CircleShape,
                shadowElevation = if (palette.isDark) 0.dp else 1.dp,
                border = BorderStroke(1.dp, palette.border),
                modifier = Modifier
                    .clip(CircleShape)
                    .clickable(onClick = onRootBadgeClick),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(dotColor),
                    )
                    Text(
                        text = badgeText,
                        color = palette.textPrimary,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }

            HeaderIconCircle(onClick = onToggleTheme) {
                Icon(
                    painter = painterResource(if (isDark) R.drawable.ic_sun else R.drawable.ic_moon),
                    contentDescription = "切换浅色/深色外观",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(18.dp),
                )
            }

            HeaderIconCircle(onClick = onRefresh, enabled = !isRefreshing) {
                if (isRefreshing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = palette.androidAccent,
                    )
                } else {
                    Icon(
                        painter = painterResource(R.drawable.ic_refresh),
                        contentDescription = "刷新",
                        tint = palette.textSecondary,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun HeaderIconCircle(
    onClick: () -> Unit,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val palette = LocalAppPalette.current
    Surface(
        color = palette.card,
        shape = CircleShape,
        shadowElevation = if (palette.isDark) 0.dp else 1.dp,
        border = BorderStroke(1.dp, palette.border),
    ) {
        IconButton(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier.size(36.dp),
        ) {
            content()
        }
    }
}

@Composable
private fun SwitchHeroCard(
    bootState: BootState,
    deviceInfo: DeviceInfo,
    linuxPartitionBytes: Long?,
    isSwitching: Boolean,
    isWideActions: Boolean,
    onRequestSwitch: (rebootAfter: Boolean) -> Unit,
    onRevertToCurrent: () -> Unit,
    onRebootNow: () -> Unit,
) {
    val palette = LocalAppPalette.current
    val currentSlot = bootState.currentSlot
    val targetSlot = bootState.targetLinuxSlot

    Surface(
        color = palette.card,
        shape = RoundedCornerShape(28.dp),
        shadowElevation = if (palette.isDark) 0.dp else 3.dp,
        border = BorderStroke(1.dp, palette.border),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .background(
                    Brush.horizontalGradient(
                        colors = listOf(
                            palette.androidAccent.copy(alpha = if (palette.isDark) 0.08f else 0.05f),
                            Color.Transparent,
                            palette.linuxAccent.copy(alpha = if (palette.isDark) 0.09f else 0.06f),
                        ),
                    ),
                )
                .padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OsStageTile(
                    modifier = Modifier.weight(1f),
                    iconRes = R.drawable.ic_android_os,
                    accent = palette.androidAccent,
                    badge = "当前运行",
                    title = deviceInfo.androidVersion.ifEmpty { "Android" },
                    subtitle = listOfNotNull(
                        deviceInfo.romVersion.takeIf { it.isNotBlank() },
                        "槽位 ${currentSlot?.suffix ?: "--"}",
                    ).joinToString(" · "),
                    isHighlighted = true,
                )

                Surface(
                    color = palette.cardMuted,
                    shape = CircleShape,
                    border = BorderStroke(1.dp, palette.border),
                ) {
                    Icon(
                        painter = painterResource(R.drawable.ic_swap),
                        contentDescription = null,
                        tint = palette.textSecondary,
                        modifier = Modifier
                            .padding(10.dp)
                            .size(18.dp),
                    )
                }

                OsStageTile(
                    modifier = Modifier.weight(1f),
                    iconRes = R.drawable.ic_linux_os,
                    accent = palette.linuxAccent,
                    badge = if (bootState.hasPendingSwitch) "待重启进入" else "目标系统",
                    title = "Linux 系统",
                    subtitle = listOfNotNull(
                        "槽位 ${targetSlot.suffix}",
                        linuxPartitionBytes?.let { Formatters.formatBytes(it) },
                    ).joinToString(" · "),
                    isHighlighted = bootState.hasPendingSwitch,
                )
            }

            if (bootState.hasPendingSwitch) {
                Surface(
                    color = palette.amberAccent.copy(alpha = 0.10f),
                    shape = RoundedCornerShape(16.dp),
                    border = BorderStroke(1.dp, palette.amberAccent.copy(alpha = 0.35f)),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "已预设下次启动进入 Linux (${bootState.nextBootSlot?.suffix ?: targetSlot.suffix})",
                                color = palette.amberAccent,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = "重启设备即可完成切换",
                                color = palette.textSecondary,
                                fontSize = 12.sp,
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(
                                onClick = onRevertToCurrent,
                                enabled = !isSwitching,
                                shape = RoundedCornerShape(12.dp),
                                border = BorderStroke(1.dp, palette.border),
                                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                            ) {
                                Text("改回当前", color = palette.textPrimary, fontSize = 13.sp)
                            }
                            Button(
                                onClick = onRebootNow,
                                enabled = !isSwitching,
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = palette.linuxAccent,
                                    contentColor = Color.White,
                                ),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            ) {
                                Text("立即重启", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            } else if (isWideActions) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    PrimarySwitchButton(
                        modifier = Modifier.weight(1f),
                        targetSlot = targetSlot,
                        isSwitching = isSwitching,
                        onClick = { onRequestSwitch(true) },
                    )
                    SecondarySlotOnlyButton(
                        isSwitching = isSwitching,
                        onClick = { onRequestSwitch(false) },
                    )
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimarySwitchButton(
                        modifier = Modifier.fillMaxWidth(),
                        targetSlot = targetSlot,
                        isSwitching = isSwitching,
                        onClick = { onRequestSwitch(true) },
                    )
                    SecondarySlotOnlyButton(
                        modifier = Modifier.fillMaxWidth(),
                        isSwitching = isSwitching,
                        onClick = { onRequestSwitch(false) },
                    )
                }
            }
        }
    }
}

@Composable
private fun OsStageTile(
    modifier: Modifier,
    @DrawableRes iconRes: Int,
    accent: Color,
    badge: String,
    title: String,
    subtitle: String,
    isHighlighted: Boolean,
) {
    val palette = LocalAppPalette.current
    Surface(
        modifier = modifier,
        color = palette.cardMuted.copy(alpha = if (palette.isDark) 0.72f else 0.75f),
        shape = RoundedCornerShape(20.dp),
        border = BorderStroke(
            width = 1.dp,
            color = if (isHighlighted) accent.copy(alpha = 0.42f) else palette.border,
        ),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(accent.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    painter = painterResource(iconRes),
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(22.dp),
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Text(
                    text = badge,
                    color = accent,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = title,
                    color = palette.textPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = subtitle,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun PrimarySwitchButton(
    modifier: Modifier,
    targetSlot: SlotId,
    isSwitching: Boolean,
    onClick: () -> Unit,
) {
    val palette = LocalAppPalette.current
    Button(
        onClick = onClick,
        enabled = !isSwitching,
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = palette.linuxAccent,
            contentColor = Color.White,
        ),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 0.dp),
        modifier = modifier.height(52.dp),
    ) {
        if (isSwitching) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = Color.White,
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text("正在写入启动槽位...", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        } else {
            Icon(
                painter = painterResource(R.drawable.ic_power_reboot),
                contentDescription = null,
                modifier = Modifier.size(19.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "重启并切换到 Linux (${targetSlot.suffix})",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun SecondarySlotOnlyButton(
    modifier: Modifier = Modifier,
    isSwitching: Boolean,
    onClick: () -> Unit,
) {
    val palette = LocalAppPalette.current
    OutlinedButton(
        onClick = onClick,
        enabled = !isSwitching,
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, palette.border),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = palette.cardMuted.copy(alpha = 0.55f),
            contentColor = palette.textPrimary,
        ),
        contentPadding = PaddingValues(horizontal = 18.dp),
        modifier = modifier.height(52.dp),
    ) {
        Text(
            text = "仅设下次启动",
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun BatteryCard(
    battery: BatteryInfo,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    val levelFraction by animateFloatAsState(
        targetValue = (battery.percent / 100f).coerceIn(0f, 1f),
        animationSpec = tween(durationMillis = 450),
        label = "battery_progress",
    )
    val accent = when {
        battery.isCharging -> palette.androidAccent
        battery.percent <= 15 -> palette.errorAccent
        else -> palette.cobaltAccent
    }

    BentoCard(
        title = "电源与续航",
        iconRes = R.drawable.ic_battery,
        accent = accent,
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Bottom,
        ) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text = "${battery.percent}%",
                    color = palette.textPrimary,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = battery.statusLabel,
                    color = accent,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
            Text(
                text = String.format(Locale.US, "%.1f °C", battery.temperatureCelsius),
                color = palette.textSecondary,
                fontSize = 13.sp,
                style = TextStyle(fontFeatureSettings = "tnum"),
            )
        }

        CapsuleProgress(fraction = levelFraction, color = accent)

        Spacer(modifier = Modifier.weight(1f, fill = false))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            MetricMini(
                label = "供电",
                value = battery.pluggedLabel,
            )
            MetricMini(
                label = "电压",
                value = if (battery.voltageMv > 0) String.format(Locale.US, "%.2f V", battery.voltageMv / 1000f) else "--",
            )
            MetricMini(
                label = "电流",
                value = battery.currentMa?.let { "${abs(it)} mA" } ?: "--",
            )
        }
    }
}

@Composable
private fun MemoryStorageCard(
    storage: StorageMemoryInfo,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    val ramUsed = (storage.ramTotalBytes - storage.ramAvailableBytes).coerceAtLeast(0L)
    val ramFrac = if (storage.ramTotalBytes > 0) ramUsed.toFloat() / storage.ramTotalBytes else 0f
    val animRam by animateFloatAsState(ramFrac.coerceIn(0f, 1f), tween(450), label = "ram")

    val dataUsed = (storage.dataTotalBytes - storage.dataAvailableBytes).coerceAtLeast(0L)
    val dataFrac = if (storage.dataTotalBytes > 0) dataUsed.toFloat() / storage.dataTotalBytes else 0f
    val animData by animateFloatAsState(dataFrac.coerceIn(0f, 1f), tween(450), label = "data")

    BentoCard(
        title = "内存与存储",
        iconRes = R.drawable.ic_chip,
        accent = palette.cobaltAccent,
        modifier = modifier,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("运行内存", color = palette.textSecondary, fontSize = 12.sp)
                Text(
                    text = "${Formatters.formatBytes(ramUsed)} / ${Formatters.formatBytes(storage.ramTotalBytes)}",
                    color = palette.textPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                )
            }
            CapsuleProgress(fraction = animRam, color = palette.cobaltAccent)
        }

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("内部存储 (/data)", color = palette.textSecondary, fontSize = 12.sp)
                Text(
                    text = "可用 ${Formatters.formatBytes(storage.dataAvailableBytes)}",
                    color = palette.textPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                )
            }
            CapsuleProgress(fraction = animData, color = palette.androidAccent)
        }

        storage.linuxPartitionBytes?.let { bytes ->
            Surface(
                color = palette.linuxAccent.copy(alpha = 0.09f),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Linux 分区 (linux)", color = palette.linuxAccent, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    Text(
                        text = Formatters.formatBytes(bytes),
                        color = palette.linuxAccent,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        style = TextStyle(fontFeatureSettings = "tnum"),
                    )
                }
            }
        }
    }
}

@Composable
private fun SystemSlotsCard(
    bootState: BootState,
    device: DeviceInfo,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    BentoCard(
        title = "系统与槽位",
        iconRes = R.drawable.ic_terminal,
        accent = palette.textSecondary,
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SlotBadge(
                modifier = Modifier.weight(1f),
                slotId = SlotId.A,
                meta = bootState.slots[SlotId.A],
                isCurrent = bootState.currentSlot == SlotId.A,
                isNext = bootState.nextBootSlot == SlotId.A,
            )
            SlotBadge(
                modifier = Modifier.weight(1f),
                slotId = SlotId.B,
                meta = bootState.slots[SlotId.B],
                isCurrent = bootState.currentSlot == SlotId.B,
                isNext = bootState.nextBootSlot == SlotId.B,
            )
        }

        HorizontalDivider(color = palette.border)

        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            CompactRow(label = "内核", value = device.kernelShort.ifEmpty { "未知" }, mono = true)
            CompactRow(label = "开机时长", value = Formatters.formatUptime(device.uptimeMillis))
            if (device.securityPatch.isNotBlank()) {
                CompactRow(label = "安全补丁", value = device.securityPatch)
            }
        }

        if (!bootState.lastError.isNullOrBlank()) {
            Text(
                text = bootState.lastError,
                color = palette.amberAccent,
                fontSize = 11.sp,
                lineHeight = 15.sp,
            )
        }
    }
}

@Composable
private fun SlotBadge(
    modifier: Modifier,
    slotId: SlotId,
    meta: SlotMetadata?,
    isCurrent: Boolean,
    isNext: Boolean,
) {
    val palette = LocalAppPalette.current
    val accent = when {
        isCurrent -> palette.androidAccent
        isNext -> palette.linuxAccent
        else -> palette.textMuted
    }

    Surface(
        modifier = modifier,
        color = palette.cardMuted.copy(alpha = 0.7f),
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, if (isCurrent || isNext) accent.copy(alpha = 0.35f) else palette.border),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = slotId.title,
                    color = palette.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = when {
                        isCurrent && isNext -> "当前"
                        isCurrent -> "运行中"
                        isNext -> "下次"
                        else -> "备用"
                    },
                    color = accent,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            val detail = if (meta != null) {
                buildList {
                    if (meta.bootable) add("可引导")
                    if (meta.successful) add("正常")
                }.ifEmpty { listOf("不可引导") }.joinToString(" · ")
            } else {
                slotId.suffix
            }
            Text(text = detail, color = palette.textSecondary, fontSize = 11.sp)
        }
    }
}

@Composable
private fun BentoCard(
    title: String,
    @DrawableRes iconRes: Int,
    accent: Color,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = LocalAppPalette.current
    Surface(
        color = palette.card,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = if (palette.isDark) 0.dp else 2.dp,
        border = BorderStroke(1.dp, palette.border),
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(accent.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painter = painterResource(iconRes),
                        contentDescription = null,
                        tint = accent,
                        modifier = Modifier.size(15.dp),
                    )
                }
                Text(
                    text = title,
                    color = palette.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            content()
        }
    }
}

@Composable
private fun CapsuleProgress(fraction: Float, color: Color) {
    val palette = LocalAppPalette.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(8.dp)
            .clip(CircleShape)
            .background(palette.cardMuted),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .height(8.dp)
                .clip(CircleShape)
                .background(color),
        )
    }
}

@Composable
private fun MetricMini(label: String, value: String) {
    val palette = LocalAppPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(text = label, color = palette.textMuted, fontSize = 11.sp)
        Text(
            text = value,
            color = palette.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            style = TextStyle(fontFeatureSettings = "tnum"),
        )
    }
}

@Composable
private fun CompactRow(
    label: String,
    value: String,
    mono: Boolean = false,
) {
    val palette = LocalAppPalette.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = label, color = palette.textSecondary, fontSize = 12.sp)
        Text(
            text = value,
            color = palette.textPrimary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun FeedbackBanner(
    message: String,
    isError: Boolean,
    onDismiss: () -> Unit,
) {
    val palette = LocalAppPalette.current
    val accent = if (isError) palette.errorAccent else palette.androidAccent
    Surface(
        color = accent.copy(alpha = 0.10f),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.35f)),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = message,
                color = palette.textPrimary,
                fontSize = 13.sp,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onDismiss) {
                Text("知道了", color = accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun ConfirmSwitchSheetContent(
    currentSlot: SlotId?,
    targetSlot: SlotId,
    rebootAfter: Boolean,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
) {
    val palette = LocalAppPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = if (rebootAfter) "切换到 Linux 并立即重启？" else "仅预设下次启动为 Linux？",
            color = palette.textPrimary,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = if (rebootAfter) {
                "将把活动槽位从 ${currentSlot?.suffix ?: "当前"} 切换到 ${targetSlot.suffix}，校验写入成功后立即重启平板。\n请确保 Android 中未保存的内容已处理。"
            } else {
                "将把下次启动槽位设为 ${targetSlot.suffix}（当前暂不重启）。之后任意时间手动重启都将进入 Linux。"
            },
            color = palette.textSecondary,
            fontSize = 14.sp,
            lineHeight = 21.sp,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = onCancel,
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, palette.border),
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp),
            ) {
                Text("取消", color = palette.textPrimary, fontSize = 14.sp)
            }
            Button(
                onClick = onConfirm,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.linuxAccent,
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp),
            ) {
                Text(
                    text = if (rebootAfter) "确认重启" else "确认设置",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun RootHelpSheetContent(
    errorDetail: String?,
    onDismiss: () -> Unit,
    onRetry: () -> Unit,
) {
    val palette = LocalAppPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            text = "需要 Root 权限才能切换槽位",
            color = palette.textPrimary,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = "切换 A/B 引导槽位需要操作底层存储与 UFS BSG 设备。请在 Magisk / KernelSU / APatch 中为「系统切换」授予超级用户权限后点击重新检测。",
            color = palette.textSecondary,
            fontSize = 14.sp,
            lineHeight = 21.sp,
        )
        if (!errorDetail.isNullOrBlank()) {
            Surface(
                color = palette.cardMuted,
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = errorDetail,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(12.dp),
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = onDismiss,
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, palette.border),
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp),
            ) {
                Text("关闭", color = palette.textPrimary)
            }
            Button(
                onClick = onRetry,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.androidAccent,
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp),
            ) {
                Text("重新检测 Root", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
