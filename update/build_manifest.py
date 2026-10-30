#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Builds a signed LogosMiner update manifest.
# usage: build_manifest.py <stage LogosMiner dir> <build number> <name> <out dir> "<notes>"
#        env SIGNING_KEY=<path to the RSA private key PEM> (required, kept OUTSIDE the repository), NODE_VER=<node version>
# Writes <out>/manifest.json, <out>/manifest.sig (base64 RSA PKCS#1 v1.5 SHA-256 over the exact manifest bytes) and
# one copy of every updatable file (files > 20 MB are split into .partNN chunks). Also rewrites <stage>/version.txt.
import sys, os, json, hashlib, subprocess, base64
stage, build, name, out, notes = sys.argv[1:6]; build = int(build)
key = os.environ.get('SIGNING_KEY') or sys.exit('set SIGNING_KEY to the private key path (never commit it)')
os.makedirs(out, exist_ok=True)
sha = lambda b: hashlib.sha256(b).hexdigest()
CH = 20 * 1024 * 1024
open(os.path.join(stage, 'version.txt'), 'w', newline='').write(f"{build}\r\n{name}")
rels = ['panel.ps1', 'README.txt', 'version.txt'] + ['bin/' + f for f in sorted(os.listdir(os.path.join(stage, 'bin')))]
files = []
for r in rels:
    b = open(os.path.join(stage, r), 'rb').read(); e = {'path': r, 'sha256': sha(b), 'size': len(b)}
    fn = r.replace('/', '_')
    if len(b) > CH:
        e['parts'] = []
        for i in range(0, len(b), CH):
            pb = b[i:i + CH]; pn = f"{fn}.part{i // CH:02d}"; open(os.path.join(out, pn), 'wb').write(pb)
            e['parts'].append({'url': pn, 'sha256': sha(pb), 'size': len(pb)})
    else:
        open(os.path.join(out, fn), 'wb').write(b); e['url'] = fn
    files.append(e)
m = {'app': 'LogosMiner', 'build': build, 'name': name, 'node': os.environ.get('NODE_VER', '0.3.4'), 'notes': notes, 'files': files}
mb = json.dumps(m, indent=1).encode()
open(os.path.join(out, 'manifest.json'), 'wb').write(mb)
sig = subprocess.check_output(['openssl', 'dgst', '-sha256', '-sign', key], input=mb)
open(os.path.join(out, 'manifest.sig'), 'w').write(base64.b64encode(sig).decode())
print('manifest ok', build, name, len(files), 'files')
