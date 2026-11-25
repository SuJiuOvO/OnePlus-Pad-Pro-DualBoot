import urllib.request
import re
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request("http://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/", headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req, context=ctx) as r:
    html = r.read().decode()
    matches = set(re.findall(r'ubuntu-base-24\.04[^\"]*arm64\.tar\.gz', html))
    for m in sorted(matches):
        print("Found:", m)
