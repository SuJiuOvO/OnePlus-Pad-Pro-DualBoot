#!/usr/bin/env python3
"""Inject a FIFO stdin wrapper for BlueZ btmgmt into caihong-hardware-mac.

On Ubuntu 24.04 (BlueZ 5.72), btmgmt hangs indefinitely when stdin is /dev/null
(such as under systemd's default StandardInput=null). Wrapping btmgmt with an
unlinked read-write FIFO keeps stdin pollable without spawning background
processes or altering command invocations.
"""

from pathlib import Path
import sys

ANCHOR = "readonly reader=/usr/local/libexec/caihong-nvram-mac\n"
MARKER = "# Ubuntu 24.04 BlueZ 5.72 btmgmt /dev/null hang workaround"
WRAPPER = f"""{ANCHOR}
{MARKER}
btmgmt()
{{
\tif [[ -t 0 || -p /dev/stdin ]]; then
\t\tcommand btmgmt "$@"
\t\treturn
\tfi
\tlocal pipe_dir rfd rc=0
\tpipe_dir=$(mktemp -d "${{TMPDIR:-/tmp}}/btmgmt-in.XXXXXX") || return 1
\tmkfifo "$pipe_dir/in" || {{ rm -rf "$pipe_dir"; return 1; }}
\texec {{rfd}}<>"$pipe_dir/in"
\trm -rf "$pipe_dir"
\ttimeout 15 btmgmt "$@" <&"$rfd" || rc=$?
\texec {{rfd}}<&-
\treturn "$rc"
}}
"""


def patch_file(target: Path) -> bool:
    text = target.read_text(encoding="utf-8")
    if MARKER in text:
        return False
    if ANCHOR not in text:
        raise RuntimeError(f"Anchor not found in {target}")
    target.write_text(text.replace(ANCHOR, WRAPPER, 1), encoding="utf-8", newline="\n")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-caihong-hardware-mac>", file=sys.stderr)
        return 2
    target = Path(sys.argv[1])
    changed = patch_file(target)
    print(f"{'Patched' if changed else 'Already patched'}: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
