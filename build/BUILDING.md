# Building the Windows binaries

Tested on Windows 10 22H2 x64 with MSYS2 (MINGW64) and Rust `x86_64-pc-windows-gnu`.

Why gnu and not MSVC: rust-rapidsnark's build script links `stdc++` and `pthread`, and the circuits' prebuilt `.lib` files are
MinGW `ar` archives. Both only link cleanly with the MinGW toolchain.

| Step | Script | Notes |
|---|---|---|
| 0 | - | MSYS2 to `C:\msys64`; `pacman -S base-devel git unzip mingw-w64-x86_64-{toolchain,cmake,nasm,clang,protobuf}`; rustup-init with the gnu host. |
| 1 | `01-rapidsnark.sh` | mman-win32, nlohmann/json 3.12.0, rapidsnark at `998383787ee8` (the circuits submodule pin) with the files in `rapidsnark-windows/`, GMP 6.2.1, then `make host_windows_x86_64_static`. Our changes vs the CI recipe: `-G "MSYS Makefiles"`, `-Duint=unsigned`, absolute `C:/msys64/include` and `C:/msys64/lib` paths for mman. |
| 2 | `02-fix-circuit-libs.sh`, `03-fix-circuit-libs-comdat.sh` | Needs the logos-blockchain-circuits **v0.5.7** windows-x86_64 tarball extracted at `$LBC_ROOT_DIR`. The official `.lib` files localize COMDAT template symbols during "symbol isolation", so references stay undefined under gnu ld. These scripts globalize them (ODR-identical, so folding is safe), give `.refptr.Fr_q` a unique name per circuit, and write `lib<name>.a`. |
| 3 | `04-node-source.sh` | logos-blockchain at tag `0.3.4`; rust-rapidsnark at the rev pinned in `Cargo.lock` (`e91187f8`) plus `patches/rust-rapidsnark-windows.patch`; a `[patch]` entry in the workspace `Cargo.toml`. |
| 4 | `05-build-node.ps1` | Env: `RAPIDSNARK_LIB_DIR`, `LBC_ROOT_DIR`, `LIBCLANG_PATH`, `RUSTFLAGS=-L native=C:/msys64/lib -l static=mman`. About 30 min on a 4-core laptop. |
| 5 | `06-build-lxpost.sh` | Path dependencies on `../logos-blockchain` (put this repo and the node checkout side by side). |
| 6 | `07-pack.sh` | Copies `app/`, the binaries and the MinGW runtime DLLs (`libgcc_s_seh-1.dll`, `libstdc++-6.dll`, `libwinpthread-1.dll` from `C:\msys64\mingw64\bin`, unmodified) into `LogosMiner/`, then zips it. With `SIGNING_KEY=...` it also writes and verifies the signed update folder. |

Check the result: `logos-blockchain-node.exe --version` should print the tag's version.
Unpatched rapidsnark at that pin makes the node panic with `ProofGeneration(Json(Error("trailing characters" ...)))` when it
goes Online. That is what the NUL-trim in the patch fixes.
