#!/usr/bin/env python3
import gzip
import sys
from pathlib import Path

default_img = Path(__file__).resolve().parent.parent / "deploy/boot/caihong-boot-linux.img"
d = Path(sys.argv[1] if len(sys.argv) > 1 else default_img).read_bytes()
s = d.find(b"IKCFG_ST")
e = d.find(b"IKCFG_ED", s)
cfg = gzip.decompress(d[s + 8 : e]).decode()
keys = (
    "SQUASHFS", "BLK_DEV_LOOP", "APPARMOR", "SECCOMP", "USER_NS",
    "CGROUP", "FUSE", "OVERLAY_FS", "XZ_DEC", "SECURITY_", "LSM",
)
for line in cfg.splitlines():
    if any(k in line for k in keys):
        print(line)
