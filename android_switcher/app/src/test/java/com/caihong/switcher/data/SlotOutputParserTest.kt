package com.caihong.switcher.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SlotOutputParserTest {

    @Test
    fun parseDump_extractsCurrentAndSlotFlags() {
        val sample = """
            Current slot: _a
            SLOT _a:
                Active      : 1
                Successful  : 1
                Bootable    : 1
            SLOT _b:
                Active      : 0
                Successful  : 1
                Bootable    : 1
        """.trimIndent()

        val parsed = SlotOutputParser.parseDump(sample)

        assertEquals(SlotId.A, parsed.currentSlot)
        assertEquals(SlotId.A, parsed.activeSlot)
        assertTrue(parsed.slots[SlotId.A]?.active == true)
        assertTrue(parsed.slots[SlotId.A]?.successful == true)
        assertFalse(parsed.slots[SlotId.B]?.active == true)
        assertTrue(parsed.slots[SlotId.B]?.bootable == true)
    }

    @Test
    fun parseActiveSlotOutput_supportsQbootctlAndBootctlFormats() {
        assertEquals(SlotId.B, SlotOutputParser.parseActiveSlotOutput("Active slot: _b\n"))
        assertEquals(SlotId.A, SlotOutputParser.parseActiveSlotOutput("Active slot: _a"))
        assertEquals(SlotId.B, SlotOutputParser.parseActiveSlotOutput("1\n"))
        assertEquals(SlotId.A, SlotOutputParser.parseActiveSlotOutput("0"))
        assertNull(SlotOutputParser.parseActiveSlotOutput("unknown"))
    }

    @Test
    fun bootState_computesTargetAndPendingCorrectly() {
        val normal = BootState(currentSlot = SlotId.A, nextBootSlot = SlotId.A)
        assertEquals(SlotId.B, normal.targetLinuxSlot)
        assertFalse(normal.hasPendingSwitch)

        val pending = BootState(currentSlot = SlotId.A, nextBootSlot = SlotId.B)
        assertEquals(SlotId.B, pending.targetLinuxSlot)
        assertTrue(pending.hasPendingSwitch)

        val inverted = BootState(currentSlot = SlotId.B, nextBootSlot = SlotId.B)
        assertEquals(SlotId.A, inverted.targetLinuxSlot)
    }

    @Test
    fun formatters_formatUptimeAndBytes() {
        assertEquals("45分钟", Formatters.formatUptime(45 * 60_000L))
        assertEquals("2小时 5分", Formatters.formatUptime((2 * 60 + 5) * 60_000L))
        assertEquals("1天 3小时 10分", Formatters.formatUptime(((24 + 3) * 60 + 10) * 60_000L))
        assertEquals("16.0 GB", Formatters.formatBytes(16L * 1024L * 1024L * 1024L))
        assertEquals("未知", Formatters.formatBytes(null))
    }

    @Test
    fun deviceInfo_extractsShortKernelRelease() {
        val dev = DeviceInfo(kernelRelease = "6.1.118-android14-11-o-gef6c734b9ecd")
        assertEquals("6.1.118", dev.kernelShort)
    }
}
