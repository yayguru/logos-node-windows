#!/bin/bash
# Step 2a: the official circuits v0.5.7 Windows .lib files localize COMDAT template symbols, so they do not link as shipped.
# Globalize symbols that are both referenced (U) and locally defined, write lib<name>.a (gnu naming).
set -e
export PATH=/mingw64/bin:$PATH
R="${LBC_ROOT_DIR:-/c/lb/lbc/logos-blockchain-circuits-v0.5.7-windows-x86_64}"   # extracted circuits v0.5.7 windows tarball
for n in poc pol poq signature; do
  cd $R/$n; rm -rf x; mkdir x; cd x; cp ../$n.lib orig.a; ar x orig.a; o=$(ls *.o)
  nm $o | awk '$1=="U"{print $2}' | sort -u > u.txt
  nm $o | awk 'NF==3 && $2 ~ /^[tdrb]$/ {print $3}' | sort -u > l.txt
  comm -12 u.txt l.txt > g.txt
  echo "$n: $(wc -l < g.txt) to globalize; unresolved non-local nlohmann: $(grep -v -x -f l.txt u.txt | grep -c nlohmann || true)"
  grep -v nlohmann g.txt | head -5
  objcopy $(sed 's/^/--globalize-symbol=/' g.txt) $o fixed.o
  rm -f ../lib$n.a; ar rcs ../lib$n.a fixed.o
done
echo FIX_DONE
