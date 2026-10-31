# Security policy (logos-node-windows, unofficial)

## Reporting a vulnerability
Please do **not** open a public issue for security problems. Use GitHub's private vulnerability reporting
("Security" tab -> "Report a vulnerability") on this repository. Include steps to reproduce and the build number
(`version.txt`). We aim to answer within a few days.

Problems in the Logos node itself should be reported to the upstream project:
https://github.com/logos-blockchain/logos-blockchain

## What the panel protects
- `data\` (node keystore and chain) is restricted with an ACL to the current user, SYSTEM and Administrators.
- The node REST API listens on `127.0.0.1` only, with CORS pinned to `http://127.0.0.1`.
- Transfers and inscriptions are built and signed locally by `lxpost.exe`; keys never leave the PC.
- Updates are accepted only if `manifest.json` carries a valid RSA-3072 (PKCS#1 v1.5, SHA-256) signature made with the
  maintainers' offline key, matching the public key embedded in `panel.ps1` (same key as `update/update_pub.pem`).
  Every downloaded file must match its SHA-256 from the signed manifest, and only `panel.ps1`, `README.txt`,
  `version.txt` and `bin\*.exe|dll` can ever be replaced. `LogosMiner.bat`, `logos-miner.ini` and `data\` are never touched.
  Update URLs must be `https://` (or `file:///` for local testing).

## Out of scope / known limits
- Binaries are not Authenticode-signed; Windows SmartScreen will warn on first run.
- Anyone with the private signing key could ship an update to users who press "Update". The key is kept offline
  and is never stored in this repository.
- This is testnet software. Do not use it to hold value you cannot afford to lose.
