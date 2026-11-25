import json, urllib.request, ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request('https://api.github.com/repos/Osilvfe/caihong-linux-rootfs/releases/tags/v0.2', headers={'User-Agent': 'curl/7.88.1'})
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        data = json.loads(response.read().decode())
        for a in data['assets']:
            if 'rootfs' in a['name'] or 'boot' in a['name']:
                print(f"{a['name']}: {a['size']} bytes\n  {a['browser_download_url']}")
except Exception as e:
    print('Error:', e)
