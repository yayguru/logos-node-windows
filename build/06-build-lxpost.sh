#!/bin/bash
# Step 5: build lxpost.exe (inscription/transfer helper). It uses path dependencies on the node source checked out
# next to this repository as ../logos-blockchain (see lxpost/Cargo.toml). Build 8 ships lxpost built against tag 0.3.2.
set -ex
cd "$(dirname "$0")/../lxpost"
cargo build --release --target x86_64-pc-windows-gnu
