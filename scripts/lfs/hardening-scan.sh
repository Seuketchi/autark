#!/bin/bash
# Scan ELF executables and shared libraries under a root for Autark's hardening, from the outside (readelf only).
root=${1:?root}
tot=0; pie=0; now=0; relro=0; cet=0; ssp=0; fort=0; missing_now=(); missing_cet=()
while IFS= read -r f; do
  hdr=$(readelf -h "$f" 2>/dev/null) || continue
  tot=$((tot+1))
  type=$(awk '/Type:/{print $2; exit}' <<<"$hdr")
  dyn=$(readelf -d "$f" 2>/dev/null); seg=$(readelf -lW "$f" 2>/dev/null)
  [ "$type" = DYN ] && pie=$((pie+1))
  if grep -qE 'BIND_NOW|FLAGS_1.*NOW' <<<"$dyn"; then now=$((now+1)); else missing_now+=("${f#$root}"); fi
  grep -q GNU_RELRO <<<"$seg" && relro=$((relro+1))
  if readelf -n "$f" 2>/dev/null | grep -q 'IBT, SHSTK'; then cet=$((cet+1)); else missing_cet+=("${f#$root}"); fi
  syms=$(readelf --dyn-syms -W "$f" 2>/dev/null)
  grep -q '__stack_chk_fail' <<<"$syms" && ssp=$((ssp+1))
  grep -qE ' __[a-z_]+_chk(@|$)' <<<"$syms" && fort=$((fort+1))
done < <(find "$root/usr/bin" "$root/usr/sbin" "$root/usr/libexec" "$root/usr/lib" -xdev -type f \( -perm -u+x -o -name '*.so*' \) ! -name '*.dbg' 2>/dev/null)
pct(){ echo "$1/$tot ($(( 100*$1/tot ))%)"; }
echo "ELF files:        $tot"
echo "PIE/shared (DYN): $(pct $pie)"
echo "Full RELRO+NOW:   $(pct $now)"
echo "RELRO segment:    $(pct $relro)"
echo "CET IBT+SHSTK:    $(pct $cet)"
echo "Stack protector:  $(pct $ssp)  (only where a function has a buffer)"
echo "FORTIFY (_chk):   $(pct $fort)  (only where a fortifiable call exists)"
echo "--- no BIND_NOW (first 25):"; printf '%s\n' "${missing_now[@]}" | head -25
echo "--- no CET (first 25):";       printf '%s\n' "${missing_cet[@]}" | head -25
