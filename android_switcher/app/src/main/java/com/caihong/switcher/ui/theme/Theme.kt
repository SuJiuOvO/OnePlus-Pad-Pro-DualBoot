package com.caihong.switcher.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

@Immutable
data class AppPalette(
    val isDark: Boolean,
    val background: Color,
    val card: Color,
    val cardMuted: Color,
    val border: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textMuted: Color,
    val androidAccent: Color,
    val linuxAccent: Color,
    val cobaltAccent: Color,
    val amberAccent: Color,
    val errorAccent: Color,
)

val LightPalette = AppPalette(
    isDark = false,
    background = Color(0xFFF3F5F9),
    card = Color(0xFFFFFFFF),
    cardMuted = Color(0xFFEEF2F8),
    border = Color(0xFFE3E8F2),
    textPrimary = Color(0xFF111827),
    textSecondary = Color(0xFF566275),
    textMuted = Color(0xFF8C97A8),
    androidAccent = Color(0xFF059669),
    linuxAccent = Color(0xFFE95420),
    cobaltAccent = Color(0xFF2563EB),
    amberAccent = Color(0xFFD97706),
    errorAccent = Color(0xFFDC2626),
)

val DarkPalette = AppPalette(
    isDark = true,
    background = Color(0xFF0C1017),
    card = Color(0xFF151C27),
    cardMuted = Color(0xFF1E2736),
    border = Color(0xFF263142),
    textPrimary = Color(0xFFF1F5F9),
    textSecondary = Color(0xFF9AA5B8),
    textMuted = Color(0xFF64748B),
    androidAccent = Color(0xFF10B981),
    linuxAccent = Color(0xFFF97316),
    cobaltAccent = Color(0xFF60A5FA),
    amberAccent = Color(0xFFFBBF24),
    errorAccent = Color(0xFFF87171),
)

val LocalAppPalette = staticCompositionLocalOf { LightPalette }

@Composable
fun CaihongSwitcherTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val palette = if (darkTheme) DarkPalette else LightPalette
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = palette.androidAccent,
            secondary = palette.linuxAccent,
            background = palette.background,
            surface = palette.card,
            surfaceVariant = palette.cardMuted,
            onBackground = palette.textPrimary,
            onSurface = palette.textPrimary,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.border,
            error = palette.errorAccent,
        )
    } else {
        lightColorScheme(
            primary = palette.androidAccent,
            secondary = palette.linuxAccent,
            background = palette.background,
            surface = palette.card,
            surfaceVariant = palette.cardMuted,
            onBackground = palette.textPrimary,
            onSurface = palette.textPrimary,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.border,
            error = palette.errorAccent,
        )
    }

    CompositionLocalProvider(LocalAppPalette provides palette) {
        MaterialTheme(
            colorScheme = colorScheme,
            content = content,
        )
    }
}
