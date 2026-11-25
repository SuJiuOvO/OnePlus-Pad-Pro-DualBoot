#!/usr/bin/env python3
"""Idempotently enable OEM CSOT NT36532 144Hz mode and non-seamless clock switching."""

from pathlib import Path
import sys


CLOCK_OLD = """#define CSOT_BASE_CLOCK_KHZ \\
\t((1500 + 118 + 20 + 100) * 2 * (2120 + 26 + 2 + 208) * 120 / 1000)"""

CLOCK_NEW = """#define CSOT_BASE_CLOCK_KHZ \\
\t((1500 + 118 + 20 + 100) * 2 * (2120 + 26 + 2 + 208) * 120 / 1000)
#define CSOT_144HZ_CLOCK_KHZ \\
\t((1500ULL + 57 + 20 + 38) * 2 * (2120 + 26 + 2 + 208) * 144 / 1000)"""

SEAMLESS_OLD = """static bool nt36532_mode_switch_is_seamless(
\t\tstruct drm_panel *panel,
\t\tconst struct drm_display_mode *old_mode,
\t\tconst struct drm_display_mode *new_mode)
{
\tstruct nt36532 *ctx = to_nt36532(panel);
\tint old_index, new_index;

\told_index = nt36532_find_mode(ctx, old_mode);
\tnew_index = nt36532_find_mode(ctx, new_mode);

\treturn old_index >= 0 && new_index >= 0 && old_index != new_index;
}"""

SEAMLESS_NEW = """static bool nt36532_mode_switch_is_seamless(
\t\tstruct drm_panel *panel,
\t\tconst struct drm_display_mode *old_mode,
\t\tconst struct drm_display_mode *new_mode)
{
\tstruct nt36532 *ctx = to_nt36532(panel);
\tint old_index, new_index;

\told_index = nt36532_find_mode(ctx, old_mode);
\tnew_index = nt36532_find_mode(ctx, new_mode);
\tif (old_index < 0 || new_index < 0 || old_index == new_index)
\t\treturn false;

\treturn ctx->panel_info->modes[old_index].mode.clock ==
\t       ctx->panel_info->modes[new_index].mode.clock;
}"""

MODES_OLD = """static const struct nt36532_panel_mode csot_modes[] = {
\tCSOT_DISPLAY_MODE(CSOT_BASE_CLOCK_KHZ, 118, 100, 26, 0x91, 0x40),
\tCSOT_DISPLAY_MODE(CSOT_BASE_CLOCK_KHZ, 118, 100, 811, 0x00, 0x80),"""

MODES_NEW = """static const struct nt36532_panel_mode csot_modes[] = {
\tCSOT_DISPLAY_MODE(CSOT_BASE_CLOCK_KHZ, 118, 100, 26, 0x91, 0x40),
\tCSOT_DISPLAY_MODE(CSOT_144HZ_CLOCK_KHZ, 57, 38, 26, 0x00, 0x00),
\tCSOT_DISPLAY_MODE(CSOT_BASE_CLOCK_KHZ, 118, 100, 811, 0x00, 0x80),"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/panel-novatek-nt36532.c>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")

    replacements = [
        ("CSOT_144HZ_CLOCK_KHZ", CLOCK_OLD, CLOCK_NEW),
        ("nt36532_mode_switch_is_seamless", SEAMLESS_OLD, SEAMLESS_NEW),
        ("csot_modes 144Hz", MODES_OLD, MODES_NEW),
    ]

    changed = False
    for name, old, new in replacements:
        if new in text:
            continue
        if old not in text:
            raise RuntimeError(f"Expected anchor not found for {name} in {path}")
        text = text.replace(old, new, 1)
        changed = True

    if changed:
        path.write_text(text, encoding="utf-8", newline="\n")
        print(f"Patched 144Hz support in {path}")
    else:
        print(f"144Hz support already present in {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
