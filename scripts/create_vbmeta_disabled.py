from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
with open(ROOT / 'deploy/stock_vbmeta_a.img', 'rb') as f:
    data = bytearray(f.read())

# AVB Flags: bit 0 = disable-verity (1), bit 1 = disable-verification (2) -> 3
data[120:124] = b'\x00\x00\x00\x03'

with open(ROOT / 'deploy/vbmeta_disabled_b.img', 'wb') as f:
    f.write(data)

print("Created deploy/vbmeta_disabled_b.img with flags = 0x3 (AVB disabled)")
