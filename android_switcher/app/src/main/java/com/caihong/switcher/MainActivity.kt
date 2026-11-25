package com.caihong.switcher

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.caihong.switcher.data.DeviceStatsReader
import com.caihong.switcher.data.SlotId
import com.caihong.switcher.data.SlotManager
import com.caihong.switcher.data.SwitchOutcome
import com.caihong.switcher.ui.SwitcherScreen
import com.caihong.switcher.ui.UiState
import com.caihong.switcher.ui.theme.CaihongSwitcherTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val statsReader = DeviceStatsReader(applicationContext)
        val slotManager = SlotManager(applicationContext, statsReader)

        setContent {
            val systemDark = isSystemInDarkTheme()
            var darkOverride by remember { mutableStateOf<Boolean?>(null) }
            val isDark = darkOverride ?: systemDark

            DisposableEffect(isDark) {
                enableEdgeToEdge(
                    statusBarStyle = if (isDark) {
                        SystemBarStyle.dark(Color.TRANSPARENT)
                    } else {
                        SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                    },
                    navigationBarStyle = if (isDark) {
                        SystemBarStyle.dark(Color.TRANSPARENT)
                    } else {
                        SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                    },
                )
                onDispose {}
            }

            CaihongSwitcherTheme(darkTheme = isDark) {
                val scope = rememberCoroutineScope()
                val lifecycleOwner = LocalLifecycleOwner.current
                var uiState by remember {
                    mutableStateOf(
                        UiState(
                            batteryInfo = statsReader.readBatteryInfo(),
                            storageMemory = statsReader.readStorageMemory(null),
                        ),
                    )
                }

                suspend fun refreshAll() {
                    uiState = uiState.copy(isRefreshing = true)
                    val devInfo = statsReader.readDeviceInfo()
                    val (bootState, linuxBytes) = slotManager.inspect()
                    val battery = statsReader.readBatteryInfo()
                    val storage = statsReader.readStorageMemory(linuxBytes)
                    uiState = uiState.copy(
                        bootState = bootState,
                        deviceInfo = devInfo,
                        batteryInfo = battery,
                        storageMemory = storage,
                        isRefreshing = false,
                    )
                }

                var hasStartedOnce by remember { mutableStateOf(false) }

                LaunchedEffect(Unit) {
                    refreshAll()
                    hasStartedOnce = true
                    while (true) {
                        delay(2500L)
                        uiState = uiState.copy(
                            batteryInfo = statsReader.readBatteryInfo(),
                            storageMemory = statsReader.readStorageMemory(uiState.storageMemory.linuxPartitionBytes),
                        )
                    }
                }

                DisposableEffect(lifecycleOwner) {
                    val observer = LifecycleEventObserver { _, event ->
                        if (event == Lifecycle.Event.ON_RESUME && hasStartedOnce) {
                            scope.launch { refreshAll() }
                        }
                    }
                    lifecycleOwner.lifecycle.addObserver(observer)
                    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
                }

                SwitcherScreen(
                    state = uiState,
                    isDark = isDark,
                    onToggleTheme = { darkOverride = !isDark },
                    onRefresh = {
                        scope.launch { refreshAll() }
                    },
                    onSwitchToSlot = { target: SlotId, rebootAfter: Boolean ->
                        scope.launch {
                            uiState = uiState.copy(isSwitching = true, bannerMessage = null)
                            when (val outcome = slotManager.switchSlot(target, rebootAfter)) {
                                is SwitchOutcome.Success -> {
                                    uiState = uiState.copy(
                                        isSwitching = false,
                                        bannerMessage = outcome.detail,
                                        bannerIsError = false,
                                    )
                                    refreshAll()
                                }
                                is SwitchOutcome.Failure -> {
                                    uiState = uiState.copy(
                                        isSwitching = false,
                                        bannerMessage = outcome.reason,
                                        bannerIsError = true,
                                    )
                                }
                            }
                        }
                    },
                    onRebootNow = {
                        scope.launch {
                            uiState = uiState.copy(isSwitching = true)
                            val res = slotManager.rebootNow()
                            if (!res.isSuccess) {
                                uiState = uiState.copy(
                                    isSwitching = false,
                                    bannerMessage = "重启失败: ${res.combinedOutput}",
                                    bannerIsError = true,
                                )
                            }
                        }
                    },
                    onDismissBanner = {
                        uiState = uiState.copy(bannerMessage = null)
                    },
                )
            }
        }
    }
}
