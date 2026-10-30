#!/bin/bash
# Step 2b: globalize every locally-defined COMDAT key symbol (ODR-identical, folding is safe), except .refptr.Fr_*
# which point at circuit-private data and are renamed per circuit. Run after 02-fix-circuit-libs.sh.
set -e
export PATH=/mingw64/bin:$PATH
R="${LBC_ROOT_DIR:-/c/lb/lbc/logos-blockchain-circuits-v0.5.7-windows-x86_64}"   # extracted circuits v0.5.7 windows tarball
for n in poc pol poq signature; do
  cd $R/$n/x; o=$(ls *.o | grep -v fixed)
  objdump -h $o | awk '$2 ~ /\$/ {print $2}' | sed 's/^[^$]*\$//' | sort -u > comdat.txt
  nm $o | awk 'NF==3 && $2 ~ /^[tdrbp]$/ {print $3}' | sort -u > l.txt
  comm -12 comdat.txt l.txt > c.txt
  grep -v '^\.refptr\.Fr_' c.txt > glob.txt || true
  grep '^\.refptr\.Fr_' c.txt > ref.txt || true
  args="$(sed 's/^/--globalize-symbol=/' glob.txt)"
  for r in $(cat ref.txt); do args="$args --redefine-sym $r=${r}__$n --rename-section .rdata\$$r=.rdata\$${r}__$n"; done
  objcopy $args $o fixed.o
  rm -f ../lib$n.a; ar rcs ../lib$n.a fixed.o
  echo "$n: globalized $(wc -l < glob.txt), renamed refptr $(wc -l < ref.txt): $(tr '\n' ' ' < ref.txt)"
  nm fixed.o | awk '$1=="U"{print $2}' | sort -u > u2.txt; nm fixed.o | awk 'NF==3 && $2 ~ /^[tdrbp]$/{print $3}' | sort -u > l2.txt; echo "  still U-and-local: $(comm -12 u2.txt l2.txt | wc -l)"
done
echo FIX2_DONE
