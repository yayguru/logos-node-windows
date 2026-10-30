# Files in this repository

| Path | What it is |
|---|---|
| `README.md` | Overview, install, update mechanism, security model, build summary, licence, disclaimer. |
| `LICENSE` | MIT licence for the project code, plus which files keep other licences. |
| `CONTRIBUTING.md` | How to contribute (PowerShell 5.1, ASCII, parse check, no secrets). |
| `SECURITY.md` | How to report vulnerabilities and what the panel protects. |
| `FILES.md` | This list. |
| `.gitignore` | Keeps build output, node data, keys and local configs out of git. |
| `app/LogosMiner.bat` | Double-click launcher: runs `panel.ps1` with Windows PowerShell and passes the command-line options through. |
| `app/panel.ps1` | The panel: node setup and start/stop, config patching for node 0.3.4, mining control, claims, wallet, send/receive, inscriptions, signed updater and rollback. Embeds the update public key. |
| `app/logos-miner.ini` | Default settings (mode, threads, API address, P2P port, public address, claim key, update URL, public testnet bootstrap peers). |
| `app/README.txt` | End-user guide shipped inside the zip. |
| `app/THIRD-PARTY-NOTICES.txt` | Where every bundled binary comes from, its licence, and the LGPL relinking notes. |
| `app/LICENSES/*` | Full licence texts for the bundled components (logos-blockchain MIT/Apache-2.0, rapidsnark and GMP LGPL-3.0, GPL-3.0, GCC Runtime Library Exception 3.1, winpthreads). |
| `update/update_pub.pem` | PUBLIC RSA-3072 key that update manifests are verified against (same key as embedded in `panel.ps1`). |
| `update/build_manifest.py` | Maintainer tool: writes `manifest.json`, the signature and the file copies for a release (needs the private key via `SIGNING_KEY`, which is kept outside the repo). |
| `update/verify_manifest.py` | Anyone can use it: checks a release's signature with the public key, plus the path allowlist and every file hash. |
| `lxpost/Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml` | Rust crate for `lxpost.exe`, with path dependencies on a `../logos-blockchain` checkout. The toolchain file comes from upstream. |
| `lxpost/src/main.rs` | `lxpost`: builds and signs inscription and transfer transactions locally (the HTTP calls are made by the panel). |
| `build/BUILDING.md` | Detailed Windows build guide. |
| `build/01-rapidsnark.sh` | Builds rapidsnark and GMP for MinGW using `build/rapidsnark-windows/`. |
| `build/02-fix-circuit-libs.sh` | Makes the official circuits v0.5.7 Windows libs linkable with gnu ld (pass 1). |
| `build/03-fix-circuit-libs-comdat.sh` | Same, pass 2 (COMDAT keys, `.refptr.Fr_q` renaming). |
| `build/04-node-source.sh` | Checks out the node tag, applies the rust-rapidsnark patch and adds the Cargo `[patch]` entry. |
| `build/05-build-node.ps1` | Runs `cargo build -p logos-blockchain-node --release` with the needed environment. |
| `build/06-build-lxpost.sh` | Builds `lxpost.exe`. |
| `build/07-pack.sh` | Assembles `LogosMiner/`, the zip and SHA256SUMS, and optionally the signed update folder. |
| `build/patches/rust-rapidsnark-windows.patch` | The only node-side change: `c_ulong` cast and NUL-trim of the proof string. |
| `build/rapidsnark-windows/*` | Build files from the logos-blockchain-circuits Windows CI recipe (`Makefile`, `src/CMakeLists.txt`, `build_gmp.sh`, `mman_patch.hpp`, `sys/uio.h`) with our small MinGW changes. Upstream licences apply. |
