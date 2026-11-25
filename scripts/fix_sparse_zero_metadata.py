#!/usr/bin/env python3
"""Ensure all ext4 metadata blocks in an Android sparse image use RAW chunks.

OnePlus / Qualcomm bootloaders can ignore CHUNK_TYPE_FILL(0) or DONT_CARE chunks
when flashing without a prior erase, leaving stale block/inode bitmaps on disk
and causing immediate ext4 checksum errors (emergency_ro) on mount.
"""

import re
import struct
import subprocess
import sys
from pathlib import Path

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4


def add_range(ranges: list[tuple[int, int]], start: int, end: int) -> None:
    if end >= start:
        ranges.append((start, end))


def collect_metadata_ranges(raw_img: Path) -> list[tuple[int, int]]:
    out = subprocess.check_output(
        ["dumpe2fs", str(raw_img)],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    ranges: list[tuple[int, int]] = [(0, 1)]

    range_patterns = [
        r"(?:Primary|Backup) superblock at (\d+)",
        r"Group descriptors at (\d+)(?:-(\d+))?",
        r"Reserved GDT blocks at (\d+)(?:-(\d+))?",
        r"Block bitmap at (\d+)",
        r"Inode bitmap at (\d+)",
        r"Inode table at (\d+)(?:-(\d+))?",
    ]
    for line in out.splitlines():
        for pat in range_patterns:
            m = re.search(pat, line)
            if m:
                s = int(m.group(1))
                e = int(m.group(2)) if (m.lastindex or 0) >= 2 and m.group(2) else s
                add_range(ranges, s, e)

    try:
        j_out = subprocess.check_output(
            ["debugfs", "-R", "blocks <8>", str(raw_img)],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for tok in j_out.split():
            if tok.isdigit():
                b = int(tok)
                add_range(ranges, b, b)
    except subprocess.CalledProcessError:
        pass

    ranges.sort()
    merged: list[tuple[int, int]] = []
    for s, e in ranges:
        if merged and s <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    return merged


def split_by_metadata(
    blk_start: int,
    blk_end: int,
    meta_ranges: list[tuple[int, int]],
) -> list[tuple[bool, int, int]]:
    """Split [blk_start, blk_end) into (is_meta, s, e) half-open segments."""
    segments: list[tuple[bool, int, int]] = []
    cur = blk_start
    for ms, me_incl in meta_ranges:
        me = me_incl + 1
        if me <= cur:
            continue
        if ms >= blk_end:
            break
        if ms > cur:
            segments.append((False, cur, ms))
            cur = ms
        overlap_end = min(me, blk_end)
        if overlap_end > cur:
            segments.append((True, cur, overlap_end))
            cur = overlap_end
        if cur >= blk_end:
            break
    if cur < blk_end:
        segments.append((False, cur, blk_end))
    return segments


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <raw_img> <sparse_img>", file=sys.stderr)
        return 2

    raw_img = Path(sys.argv[1])
    sparse_img = Path(sys.argv[2])
    tmp_sparse = sparse_img.with_suffix(sparse_img.suffix + ".tmp")

    meta_ranges = collect_metadata_ranges(raw_img)
    total_meta_blocks = sum(e - s + 1 for s, e in meta_ranges)

    converted_chunks = 0
    converted_blocks = 0
    new_chunks = 0

    with (
        raw_img.open("rb") as f_raw,
        sparse_img.open("rb") as f_in,
        tmp_sparse.open("wb") as f_out,
    ):
        hdr = f_in.read(28)
        magic, maj, minv, fhdr_sz, chdr_sz, blk_sz, total_blks, total_chunks, img_csum = struct.unpack(
            "<IHHHHIIII", hd
        )
        if magic != SPARSE_MAGIC or fhdr_sz != 28 or chdr_sz != 12:
            raise RuntimeError(f"Unsupported sparse header in {sparse_img}")

        # Write placeholder header; patch total_chunks at end
        f_out.write(hdr)

        cur_blk = 0
        for _ in range(total_chunks):
            ch = f_in.read(chdr_sz)
            ctype, res, cblks, csz = struct.unpack("<HHII", ch)
            payload_sz = csz - chdr_sz
            payload = f_in.read(payload_sz)
            blk_end = cur_blk + cblks

            if ctype in (CHUNK_FILL, CHUNK_DONT_CARE) and cblks > 0:
                segs = split_by_metadata(cur_blk, blk_end, meta_ranges)
                if any(is_meta for is_meta, _, _ in segs):
                    converted_chunks += 1
                    for is_meta, s, e in segs:
                        seg_blks = e - s
                        if is_meta:
                            f_raw.seek(s * blk_sz)
                            raw_bytes = f_raw.read(seg_blks * blk_sz)
                            if len(raw_bytes) != seg_blks * blk_sz:
                                raise RuntimeError(f"Short read from {raw_img} at block {s}")
                            f_out.write(
                                struct.pack(
                                    "<HHII",
                                    CHUNK_RAW,
                                    0,
                                    seg_blks,
                                    chdr_sz + len(raw_bytes),
                                )
                            )
                            f_out.write(raw_bytes)
                            converted_blocks += seg_blks
                        else:
                            f_out.write(
                                struct.pack("<HHII", ctype, res, seg_blks, chdr_sz + len(payload))
                            )
                            f_out.write(payload)
                        new_chunks += 1
                    cur_blk = blk_end
                    continue

            f_out.write(ch)
            f_out.write(payload)
            new_chunks += 1
            cur_blk = blk_end

        if cur_blk != total_blks:
            raise RuntimeError(f"Block count mismatch: walked {cur_blk}, header says {total_blks}")

        f_out.seek(0)
        f_out.write(
            struct.pack(
                "<IHHHHIIII",
                magic,
                maj,
                minv,
                fhdr_sz,
                chdr_sz,
                blk_sz,
                total_blks,
                new_chunks,
                img_csum,
            )
        )

    tmp_sparse.replace(sparse_img)
    print(
        f"Sparse metadata hardening complete: {total_meta_blocks} metadata blocks tracked, "
        f"split {converted_chunks} non-RAW chunks ({converted_blocks} metadata blocks -> CHUNK_RAW), "
        f"chunks {total_chunks} -> {new_chunks}, size={sparse_img.stat().st_size / (1024*1024):.1f} MiB"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
