#!/bin/bash
# Step 1 (MSYS2 MINGW64 shell): build rapidsnark + GMP for x86_64-pc-windows-gnu, following the
# logos-blockchain-circuits 'build-windows' CI recipe (files in ./rapidsnark-windows). Output: $WORK/rapidsnark/package/lib
set -ex
export PATH=/mingw64/bin:$PATH
R="$(cd "$(dirname "$0")" && pwd)/rapidsnark-windows"
WORK="${WORK:-/c/lb/src}"   # where sources are cloned
mkdir -p "$WORK" && cd "$WORK"
[ -d mman-win32 ] || git clone https://github.com/alitrack/mman-win32.git
( cd mman-win32 && ./configure --prefix= --cc=gcc && make && make install )
mkdir -p /include/nlohmann /include/sys
[ -f /include/nlohmann/json.hpp ] || curl -fL -o /include/nlohmann/json.hpp https://github.com/nlohmann/json/releases/download/v3.12.0/json.hpp
[ -d rapidsnark ] || { git clone https://github.com/iden3/rapidsnark.git && cd rapidsnark && git checkout 998383787ee86bcb6bfb8741e9a638d203c08eae && git submodule update --init --recursive && cd ..; }
cd rapidsnark
cp $R/Makefile Makefile
cp $R/windows.src-CMakeLists.txt src/CMakeLists.txt
cp $R/windows.mman_patch.hpp /include/mman_patch.hpp
cp $R/windows.uio.h /include/sys/uio.h
cp $R/windows.build_gmp.sh build_gmp.sh
mkdir -p depends
[ -f depends/gmp-6.2.1.tar.xz ] || curl -fL -o depends/gmp-6.2.1.tar.xz https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz
[ -d depends/gmp/package ] || ./build_gmp.sh host
make host_windows_x86_64_static
find package build_prover -name '*.a' -o -name '*.dll' -o -name '*.exe' | head -50
echo RS_DONE
