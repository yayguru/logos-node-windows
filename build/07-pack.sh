#!/bin/bash
# Step 6: assemble the release folder + zip, and (optionally) the signed update directory.
# usage: build/07-pack.sh <node exe> <lxpost exe> <dir with the 3 MinGW runtime DLLs> <build number> <name> [out dir]
#   SIGNING_KEY=<private key PEM> to also write the signed update manifest into <out>/update (needs the maintainers' key).
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"; NODE="$1"; LX="$2"; DLLS="$3"; BUILD="$4"; NAME="$5"; OUT="${6:-$HERE/dist}"
S="$OUT/stage/LogosMiner"; rm -rf "$OUT/stage"; mkdir -p "$S/bin" "$S/LICENSES"
cp "$HERE"/app/{panel.ps1,LogosMiner.bat,README.txt,THIRD-PARTY-NOTICES.txt,logos-miner.ini} "$S/"; cp "$HERE"/app/LICENSES/* "$S/LICENSES/"
cp "$NODE" "$S/bin/logos-blockchain-node.exe"; cp "$LX" "$S/bin/lxpost.exe"
for d in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do cp "$DLLS/$d" "$S/bin/"; done
printf '%s\r\n%s' "$BUILD" "$NAME" > "$S/version.txt"
if [ -n "$SIGNING_KEY" ]; then rm -rf "$OUT/update"; python3 "$HERE/update/build_manifest.py" "$S" "$BUILD" "$NAME" "$OUT/update" "build $BUILD"; python3 "$HERE/update/verify_manifest.py" "$OUT/update"; fi
( cd "$OUT/stage" && rm -f "../LogosMiner-win64-$NAME.zip" && zip -qr9 "../LogosMiner-win64-$NAME.zip" LogosMiner )
( cd "$OUT" && sha256sum "LogosMiner-win64-$NAME.zip" stage/LogosMiner/bin/* stage/LogosMiner/panel.ps1 > "SHA256SUMS-$NAME" && cat "SHA256SUMS-$NAME" )
