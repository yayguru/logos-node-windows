#!/bin/bash
# Step 3 (MSYS2 shell): get the node source at the release tag and point it at the patched rust-rapidsnark.
set -ex
WORK="${WORK:-/c/lb/src}"; TAG="${TAG:-0.3.4}"; HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$WORK"
[ -d logos-blockchain ] || git clone https://github.com/logos-blockchain/logos-blockchain.git
( cd logos-blockchain && git fetch origin tag "$TAG" --no-tags && git checkout -q "$TAG" && git describe --tags )
# rust-rapidsnark at the revision pinned in logos-blockchain's Cargo.lock, plus the Windows patch
REV=$(grep -A2 'name = "rust-rapidsnark"' logos-blockchain/Cargo.lock | sed -n 's/.*#\([0-9a-f]\{40\}\)".*/\1/p' | head -1)
[ -d rust-rapidsnark ] || git clone https://github.com/logos-blockchain/logos-blockchain-rust-rapidsnark.git rust-rapidsnark
( cd rust-rapidsnark && git checkout -q "$REV" && (git apply --check "$HERE/patches/rust-rapidsnark-windows.patch" 2>/dev/null && git apply "$HERE/patches/rust-rapidsnark-windows.patch" || echo "patch already applied?") )
cd logos-blockchain
grep -q 'patch."https://github.com/logos-blockchain/logos-blockchain-rust-rapidsnark.git"' Cargo.toml || printf '\n[patch."https://github.com/logos-blockchain/logos-blockchain-rust-rapidsnark.git"]\nrust-rapidsnark = { path = "../rust-rapidsnark/crates" }\n' >> Cargo.toml
