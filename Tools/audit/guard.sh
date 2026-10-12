#!/bin/zsh
# Usage: guard.sh <outdir> <kill-MB> -- command...
# Runs the command with stdout/stderr in <outdir>, logs its memory FOOTPRINT
# (not RSS: compressed pages leave RSS but count against the host) every
# second to <outdir>/mem.log, and kills it past <kill-MB>. Follows the real
# child when the command is a wrapper such as /usr/bin/time. Never globs.
out=$1; snap=999999; limit=$2; shift 3
mkdir -p "$out"
: > "$out/mem.log"
start=$(date +%s)
"$@" > "$out/stdout" 2> "$out/stderr" &
P=$!
snapped=0
while kill -0 $P 2>/dev/null; do
  C=$(pgrep -P $P | head -1); W=${C:-$P}
  fp=$(footprint -p $W 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="Footprint:"){v=$(i+1);u=$(i+2); if(u=="GB")v*=1024; else if(u=="KB")v/=1024; else if(u=="B")v=0; print int(v); exit}}')
  t=$(( $(date +%s) - start ))
  echo "$t ${fp:-?}" >> "$out/mem.log"
  if [[ -n $fp && $fp -gt $snap && $snapped == 0 ]]; then
    snapped=1
    echo "snapshot at ${fp}MB t=$t" >> "$out/mem.log"
    heap -s $P > "$out/heap.txt" 2>&1
    sample $P 5 -file "$out/sample.txt" > /dev/null 2>&1
  fi
  if [[ -n $fp && $fp -gt $limit ]]; then
    kill $W $P
    echo "KILLED at ${fp}MB t=$t" >> "$out/mem.log"
    break
  fi
  sleep 1
done
wait $P
echo "exit $? after $(( $(date +%s) - start ))s" >> "$out/mem.log"
