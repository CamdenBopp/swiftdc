#!/bin/zsh
# check.sh <built-corpus-dir>
#
# Checks each dylib build.sh produced against MANIFEST.tsv: the sha256 of
# its __TEXT,__text bytes must be the recorded one, so the scored code is
# the code the tables were written against. Exits nonzero on any mismatch
# or missing dylib. A new toolchain changes code generation: then the
# corpus must be re-scored, not the manifest edited to match.
set -u
built=$1 here=${0:A:h}
tmp=$(mktemp -d) bad=0 count=0
while IFS=$'\t' read -r name hash _; do
  [[ $name == \#* || -z $name ]] && continue
  count=$((count + 1))
  if [[ ! -f $built/$name ]]; then echo "missing: $name" >&2; bad=$((bad + 1)); continue; fi
  xcrun segedit $built/$name -extract __TEXT __text $tmp/text 2>/dev/null
  got=$(shasum -a 256 $tmp/text | cut -d' ' -f1)
  [[ $got == $hash ]] || { echo "differs: $name" >&2; bad=$((bad + 1)); }
done < $here/MANIFEST.tsv
rm -rf $tmp
echo "corpus: $count dylibs, $bad not matching the manifest"
(( bad == 0 ))
