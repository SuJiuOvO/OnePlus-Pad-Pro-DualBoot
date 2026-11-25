#!/bin/bash
set -eo pipefail

DEST_DIR="${DEST_DIR:-/var/cache/arch_rootfs}"
mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

URL_PART00="https://github.com/Osilvfe/caihong-linux-rootfs/releases/download/v0.2/caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-00"
URL_PART01="https://github.com/Osilvfe/caihong-linux-rootfs/releases/download/v0.2/caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-01"

echo "=== Downloading Arch Linux RootFS Parts ==="
if [ ! -f "caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-00" ]; then
    echo "Downloading part-00..."
    curl -L -C - -o "caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-00" "$URL_PART00"
else
    echo "part-00 already exists, skipping."
fi

if [ ! -f "caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-01" ]; then
    echo "Downloading part-01..."
    curl -L -C - -o "caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-01" "$URL_PART01"
else
    echo "part-01 already exists, skipping."
fi

echo "=== Concatenating RootFS stream ==="
cat caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-00 caihong-rootfs-7.3.0-g77f2f22ff4f9.ext4.sparse.img.zst.part-01 > caihong-rootfs.ext4.sparse.img.zst

echo "=== Decompressing with zstd ==="
zstd -d --rm caihong-rootfs.ext4.sparse.img.zst -o caihong-arch-rootfs.ext4.sparse.img

echo "=== Arch Linux Sparse RootFS Ready! ==="
ls -lh caihong-arch-rootfs.ext4.sparse.img
