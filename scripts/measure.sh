#!/bin/bash
# usage: scripts/measure.sh <pgrep pattern> <seconds>
# Prints each matching process's phys_footprint, the total, and the average CPU over <seconds>.
set -euo pipefail
P=$(pgrep -f "$1")
total=0
for p in $P; do
  name=$(ps -o comm= -p "$p" | sed 's|.*/||')
  kb=$(footprint "$p" 2>/dev/null | awk '/phys_footprint:/{v=$2; u=$3; if (u=="MB") v*=1024; if (u=="GB") v*=1048576; print int(v); exit}')
  echo "$p $name ${kb:-0} KB"
  total=$((total + ${kb:-0}))
done
echo "total footprint: $((total / 1024)) MB"
cpu() { ps -o time= -p $(echo $P | tr ' ' ',') | awk -F'[:.]' '{s+=$1*60+$2+$3/100} END{printf "%.2f", s}'; }
a=$(cpu); sleep "$2"; b=$(cpu)
echo "CPU avg over ${2}s: $(echo "($b-$a)/$2*100" | bc -l | cut -c1-5)%"
