# Building the Windows binaries

Tested on Windows 10 22H2 x64 with MSYS2 (MINGW64) and Rust `x86_64-pc-windows-gnu`.

Why gnu and not MSVC: rust-rapidsnark's build script links `stdc++` and `pthread`, and the circuits' prebuilt `.lib` files are
MinGW `ar` archives. Both only link cleanly with the MinGW toolchain.

| Step | Script | Notes |
|---|---|---|
| 0 | - | MSYS2 to `C:\msys64`; `pacman -S base-devel git unzip mingw-w64-x86_64-{toolchain,cmake,nasm,clang,protobuf}`; rustup-init with the gnu host. |
| 1 | `01-rapidsnark.sh` | mman-win32, nlohmann/json 3.12.0, rapidsnark at `998383787ee8` (the circuits submodule pin) with the files in `rapidsnark-windows/`, GMP 6.2.1, then `make host_windows_x86_64_static`. Our changes vs the CI recipe: `-G "MSYS Makefiles"`, `-Duint=unsigned`, absolute `C:/msys64/include` and `C:/msys64/lib` paths for mman. |
| 2 | `02-fix-circuit-libs.sh`, `03-fix-circuit-libs-comdat.sh` | Needs the logos-blockchain-circuits **v0.5.7** windows-x86_64 tarball extracted at `$LBC_ROOT_DIR`. The official `.lib` files localize COMDAT template symbols during "symbol isolation", so references stay undefined under gnu ld. These scripts globalize them (ODR-identical, so folding is safe), give `.refptr.Fr_q` a unique name per circuit, and write `lib<name>.a`. |
| 3 | `04-node-source.sh` | logos-blockchain at tag `0.3.4`; rust-rapidsnark at the rev pinned in `Cargo.lock` (`e91187f8`) plus `patches/rust-rapidsnark-windows.patch`; `patches/node-0.3.4-v11.patch` then `patches/node-0.3.4-v12-memfix.patch` on the node source (see below); a `[patch]` entry in the workspace `Cargo.toml`. |
| 4 | `05-build-node.ps1` | Env: `RAPIDSNARK_LIB_DIR`, `LBC_ROOT_DIR`, `LIBCLANG_PATH`, `RUSTFLAGS=-L native=C:/msys64/lib -l static=mman`. About 30 min on a 4-core laptop. |
| 5 | `06-build-lxpost.sh` | Path dependencies on `../logos-blockchain` (put this repo and the node checkout side by side). |
| 6 | `07-pack.sh` | Copies `app/`, the binaries and the MinGW runtime DLLs (`libgcc_s_seh-1.dll`, `libstdc++-6.dll`, `libwinpthread-1.dll` from `C:\msys64\mingw64\bin`, unmodified) into `LogosNode/`, then zips it. With `SIGNING_KEY=...` it also writes and verifies the signed update folder. |

Check the result: `logos-blockchain-node.exe --version` should print the tag's version.
Unpatched rapidsnark at that pin makes the node panic with `ProofGeneration(Json(Error("trailing characters" ...)))` when it
goes Online. That is what the NUL-trim in the patch fixes.

## Relinking the LGPL components (rapidsnark, GMP)
The node links rapidsnark and GMP statically. To use your own (modified) versions:
1. Build them with `build/01-rapidsnark.sh` (or your own MinGW build) so you get `librapidsnark.a`, `libfr.a`, `libfq.a` and `libgmp.a`.
2. Point `RAPIDSNARK_LIB_DIR` at that folder and run steps 4 and 5 (`04-node-source.sh`, `05-build-node.ps1`) again.
3. Replace `bin\logos-blockchain-node.exe` in your install with the result.
The node source is public (upstream tag `0.3.4`) and the only changes are `patches/rust-rapidsnark-windows.patch` and
`patches/node-0.3.4-v11.patch`, so the
whole program can be rebuilt and relinked. If you need the exact sources used for a release, open an issue.

## Node patch (builds 10 and 11)
`patches/node-0.3.4-v11.patch` is the full diff against tag `0.3.4` (`f7ab0323`) used for build 11, excluding the Cargo
`[patch]` entry that `04-node-source.sh` adds. It contains:
- Build 10: a backport of upstream PR 3986 (Blend winning-slot pre-poll, commit `9739b5fc`): `nodes/node/binary/src/generic_services/blend/pol.rs`,
  `services/blend/src/epoch_info.rs`, `services/chain/chain-leader/src/leadership.rs`, `utils/src/tokio/stream.rs`, `Cargo.lock`.
- Build 11: the Blend claim-jam fix and PoW re-claiming: `services/blend/src/pending.rs`, `services/blend/src/edge/current_epoch.rs`,
  `services/blend/src/core/mod.rs`, `services/pow/src/service.rs`, and tests in `services/blend/src/edge/tests/`.
  See `CHANGELOG.md`, build 11.

Tests used for build 11 (same environment as step 4):
`cargo test -p logos-blockchain-blend-service --release --lib -- tests --test-threads=1` and
`cargo test -p logos-blockchain-pow-service --release --lib -- tests --test-threads=1`.

## Node patch (unreleased memory fix)
`patches/node-0.3.4-v12-memfix.patch` applies on top of the v11 patch. It stops the wallet from cloning every
tracked voucher Merkle path into a new map on every block (the same leak as the long-running Linux node).
Paths that a new voucher does not settle are shared with the previous per-block `WalletState` via
`push_with_lazy_paths`. A regression test applies 32 tracked vouchers plus 3000 further blocks and checks
that anonymous RSS stays nearly flat. This is source only; there is no build 12 release yet.
