import urllib.request
import os
import ssl
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

files = [
    {
        "url": "https://github.com/Osilvfe/caihong-linux-rootfs/releases/download/v0.2/caihong-boot-linux-7.3.0-g77f2f22ff4f9.img",
        "dest": str(ROOT / "deploy/boot/caihong-boot-linux.img")
    },
    {
        "url": "https://github.com/Osilvfe/caihong-linux-rootfs/releases/download/v0.2/linux-caihong-7.3.0.g77f2f22ff4f9-1-aarch64.pkg.tar.zst",
        "dest": str(ROOT / "deploy/boot/linux-caihong-modules.pkg.tar.zst")
    },
    {
        "url": "https://github.com/Osilvfe/caihong-linux-rootfs/releases/download/v0.2/caihong-platform-archlinuxarm-edb349d.tar.zst",
        "dest": str(ROOT / "deploy/boot/caihong-platform-assets.tar.zst")
    }
]

for item in files:
    dest = item["dest"]
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 1000000:
        print(f"Already exists: {dest}")
        continue
    print(f"Downloading {item['url']} -> {dest}...")
    req = urllib.request.Request(item["url"], headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, context=ctx) as resp, open(dest, "wb") as f:
        total = int(resp.headers.get("content-length", 0))
        downloaded = 0
        while True:
            chunk = resp.read(1024 * 512)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)
            if total > 0:
                percent = downloaded / total * 100
                print(f"\r  {downloaded / (1024*1024):.1f}/{total / (1024*1024):.1f} MB ({percent:.1f}%)", end="", flush=True)
        print()
    print(f"Finished: {dest} ({os.path.getsize(dest)} bytes)")
