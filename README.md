# LogosMiner for Windows

A native Windows (no WSL) package for running a **Logos blockchain testnet node and miner**. It has a simple
menu-driven PowerShell panel. Unzip it, double-click `LogosMiner.bat`, and pick "full node" or "mine only".

> **Not affiliated.** This is a community project. It is not made, endorsed or supported by the Logos project, IFT
> or the logos-blockchain maintainers. "Logos" is used only to describe what the software works with.

Current release: **build 8**, bundling `logos-blockchain-node` **0.3.4** (upstream tag `0.3.4`, commit `f7ab0323`).

## Features
- One-click node setup: **full node** (opens the P2P port in Windows Firewall, with an optional public address) or **mine only**
  (outbound only, no admin rights, no Developer Mode).
- Mining on/off, CPU thread selection (`auto` = half of your threads), restart, status with sync, height and mining state,
  log tail, and an automatic restart if a slow PC fails to start the mining service.
- Auto-claim of mining rewards with no balance cap. The node default of 2,000,000,000 is raised to the maximum. Manual claim is also available.
- Wallet balance, **Send** and **Receive** coins, and **Inscribe** text, images or files on-chain. Every action shows the exact fee and needs
  a typed confirmation. A `--dry-run` mode is available.
- **Signed updates** (menu U): downloads only changed files, checks every hash and the release signature, backs up the old files,
  and rolls back automatically if the new node does not come up. Manual rollback is also available.
- Node 0.3.4 config migration: on first start the node converts `data\user_config.yaml` and keeps `user_config.yaml.0.3.2.bak`.
  The panel runs `--check-config` before every start, and its rollback restores the matching config.
- Hardening: the REST API is on 127.0.0.1 only, CORS is pinned to loopback, and `data\` is locked by ACL to your user, SYSTEM and Administrators.

## Install (users)
1. Download `LogosMiner-win64-<version>.zip` from the Releases page and compare its SHA-256 with the published `SHA256SUMS`.
2. Unzip anywhere (for example `C:\LogosMiner`) and double-click `LogosMiner.bat`.
3. Choose `1` (full node) or `2` (mine only). On first start a new node identity and keystore are created in `data\`.
   **Back up `data\keystore.yaml` and never share it.**
4. SmartScreen will warn because the binaries are not code-signed: "More info" -> "Run anyway", but only for a zip you verified.

See [`app/README.txt`](app/README.txt) for the full user guide, which also ships inside the zip.

## How updates work (signed manifest)
- The panel fetches `manifest.json` and `manifest.sig` from the update URL. The default is the project's release host; it can be changed with
  `update_url=` in `logos-miner.ini` (`https://` only, or `file:///` for local tests).
- `manifest.sig` is a base64 **RSA-3072 PKCS#1 v1.5 / SHA-256** signature over the exact bytes of `manifest.json`. The panel
  checks it against the public key embedded in `panel.ps1` and refuses the update if it does not match.
- The manifest lists `path`, `sha256`, `size` and a `url` (or 20 MB `parts`) for each file. The panel only accepts paths matching
  `panel.ps1 | README.txt | version.txt | bin/*.exe | bin/*.dll` and checks each file's SHA-256 before swapping anything.
- An update only installs if its `build` number is higher than the installed `version.txt`.
- The old files go to `update\backup-<time>\`. If the node does not come back within a few minutes, they are restored.
  Build 8 also saves a copy of the config with each backup and restores it on rollback.
- `LogosMiner.bat`, `logos-miner.ini` and `data\` (keys, chain) are never changed by an update.

### Verify a release yourself (public key only)
```
python3 update/verify_manifest.py <folder with manifest.json, manifest.sig and the files> update/update_pub.pem
# or just the signature:
base64 -d manifest.sig > manifest.sig.bin
openssl dgst -sha256 -verify update/update_pub.pem -signature manifest.sig.bin manifest.json
```
The key in `update/update_pub.pem` is the same key embedded in `app/panel.ps1` (`$UpdPubMod` + `$UpdPubExp` = 65537).
The private signing key is held offline by the maintainers and is **not** in this repository.

## Security model (short)
See [SECURITY.md](SECURITY.md). Keys stay on your PC. Transactions are built and signed locally by `lxpost.exe`. The panel only
talks to the local node, the community explorer (Receive/Send look-ups and links) and, when you use menu U, the update host.

## Build from source
The node is built from the official upstream source with MSYS2 MinGW-w64 (`x86_64-pc-windows-gnu`). See [build/BUILDING.md](build/BUILDING.md).
In short:
1. Install MSYS2 (`base-devel git unzip mingw-w64-x86_64-{toolchain,cmake,nasm,clang,protobuf}`) and rustup with a gnu host.
2. `build/01-rapidsnark.sh`: build rapidsnark and GMP with the circuits repo's Windows recipe (`build/rapidsnark-windows/`).
3. Extract the logos-blockchain-circuits v0.5.7 Windows tarball, then run `build/02-*.sh` and `build/03-*.sh` so the shipped `.lib` files link with gnu ld.
4. `build/04-node-source.sh`: check out tag `0.3.4` and apply `build/patches/rust-rapidsnark-windows.patch`.
5. `build/05-build-node.ps1`: `cargo build -p logos-blockchain-node --release`.
6. `build/06-build-lxpost.sh`, then `build/07-pack.sh` to assemble the zip (and a signed update folder if you hold a signing key).

The only node-side change is the rust-rapidsnark patch: a `c_ulong` cast (long is 32-bit on Windows) and trimming NUL padding
from the proof string. Nothing else in the node source is modified.

## Licence
The project code is under the [MIT licence](LICENSE). `lxpost/` is MIT OR Apache-2.0. Release zips also contain the upstream node
(MIT OR Apache-2.0), rapidsnark and GMP (LGPL-3.0, statically linked) and the MinGW/GCC runtime DLLs (GPL-3.0 with the GCC Runtime Library
Exception, and the winpthreads licence). All their licence texts and the LGPL relinking notes are in `app/LICENSES/` and
`app/THIRD-PARTY-NOTICES.txt` and must ship with every binary release.

## Disclaimer
Testnet software, provided "as is", without warranty of any kind. Mining uses a lot of CPU and power. Inscriptions and transfers are
public, permanent and final. You are responsible for your keys and backups. Use at your own risk.
