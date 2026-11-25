import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request('https://api.github.com/repos/Osilvfe/caihong-linux-rootfs/releases/tags/v0.2', headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req, context=ctx) as r:
    data = json.loads(r.read())
    print("Release Tag:", data.get("tag_name"))
    for a in data.get("assets", []):
        print(f"  {a['name']} ({a['size'] / (1024*1024):.2f} MB) -> {a['browser_download_url']}")
