#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Verifies a LogosMiner update directory with the PUBLIC key only.
# usage: verify_manifest.py <dir with manifest.json + manifest.sig + files> [public key PEM, default: update_pub.pem next to this script]
# Checks: RSA-3072 PKCS#1 v1.5 SHA-256 signature over the exact manifest.json bytes, the path allowlist the panel enforces,
# and the SHA-256/size of every file (or every part) listed in the manifest.
import sys, os, json, hashlib, base64, subprocess, tempfile, re
d = sys.argv[1]
pub = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'update_pub.pem')
mb = open(os.path.join(d, 'manifest.json'), 'rb').read()
sig = base64.b64decode(open(os.path.join(d, 'manifest.sig')).read().strip())
with tempfile.NamedTemporaryFile(delete=False) as t: t.write(sig)
try:
    r = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', pub, '-signature', t.name], input=mb, capture_output=True)
finally: os.unlink(t.name)
print('signature:', r.stdout.decode().strip() or r.stderr.decode().strip())
ok = r.returncode == 0
m = json.loads(mb)
allow = re.compile(r'^(panel\.ps1|README\.txt|version\.txt|bin/[A-Za-z0-9._+-]+\.(exe|dll))$')
for f in m['files']:
    if not allow.match(f['path']): print('NOT ALLOWED path', f['path']); ok = False; continue
    parts = f.get('parts') or [{'url': f['url'], 'sha256': f['sha256'], 'size': f['size']}]
    whole = hashlib.sha256()
    for p in parts:
        b = open(os.path.join(d, p['url']), 'rb').read(); whole.update(b)
        if hashlib.sha256(b).hexdigest() != p['sha256'] or len(b) != p['size']: print('BAD', p['url']); ok = False
    if whole.hexdigest() != f['sha256']: print('BAD whole file', f['path']); ok = False
    else: print('ok', f['path'], f['size'])
print('build', m['build'], m['name'], 'node', m.get('node'), '->', 'ALL OK' if ok else 'FAILED')
sys.exit(0 if ok else 1)
