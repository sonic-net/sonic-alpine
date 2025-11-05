#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Inputs
source ../.env
: "${OTG_API:?Missing OTG_API in .env}"
: "${OTG_LOCATION_P1:=eth1}"
: "${OTG_LOCATION_P2:=eth2}"
: "${OTG_LOCATION_P3:=}"
: "${OTG_LOCATION_P4:=}"

command -v jq >/dev/null || { echo "ERROR: jq is required." >&2; exit 1; }

# Output locations
OUTDIR="../results/runs"; mkdir -p "$OUTDIR"
TS="$(date +%Y%m%d_%H%M%S)"
CSV="$OUTDIR/bench_${TS}.csv"
echo "name,pps,pktsize,tx_from_p1,rx_on_p2,loss_pct" > "$CSV"

# Test matrix
pps_list=(1000 5000 10000 25000 50000)
size_list=(64 256 512 1024 1500)

# Which pairs to bench
pairs=("p12 ${OTG_LOCATION_P1} ${OTG_LOCATION_P2}")
if [[ -n "${OTG_LOCATION_P3}" && -n "${OTG_LOCATION_P4}" ]]; then
  pairs+=("p34 ${OTG_LOCATION_P3} ${OTG_LOCATION_P4}")
fi

# Packets per test
PKTS="${PKTS:-10000}" 
echo "Running with PKTS=$PKTS per test"

# --- Run tests across all pairs, PPS, and sizes ---
for pair in "${pairs[@]}"; do
  set -- $pair
  pair_name="$1"; txl="$2"; rxl="$3"

  echo -e "\n\033[1;34m[PAIR $pair_name]\033[0m  txl=$txl  rxl=$rxl"

  for pps in "${pps_list[@]}"; do
    echo -e "  \033[1;36m>> PPS=$pps pkts=$PKTS\033[0m"

    for sz in "${size_list[@]}"; do
      name="${pair_name}_f_${pps}pps_${sz}B"
      printf "    Flow %-22s (size=%-4s) ... " "$name" "$sz"

      tmpf="$(mktemp)"
      
      # Show progress while running
      otgen create flow -n "$name" -s 1.1.1.1 -d 2.2.2.2 \
        --size "$sz" -r "$pps" -c "$PKTS" \
        --tx p1 --rx p2 --txl "$txl" --rxl "$rxl" \
      | otgen run -k -a "$OTG_API" -y -m flow > "$tmpf" 2>&1 &
      
      # Show spinner while waiting
      pid=$!
      spin='-\|/'
      i=0
      while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r    Flow %-22s (size=%-4s) ... ${spin:$i:1} running" "$name" "$sz"
        sleep 0.2
      done
      wait $pid
      
      # Clear spinner and reprint
      printf "\r    Flow %-22s (size=%-4s) ... " "$name" "$sz"
      
      final_json=$(tail -1 "$tmpf")
      rm -f "$tmpf"
      
      tx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_tx // 0' 2>/dev/null || echo "0")
      rx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_rx // 0' 2>/dev/null || echo "0")

      if [[ -n "${tx:-}" && "${tx:-0}" -gt 0 && -n "${rx:-}" ]]; then
        loss="$(awk -v a="$tx" -v b="$rx" 'BEGIN{printf "%.3f", (a-b)*100.0/a}')"
        printf "TX=%-7s RX=%-7s LOSS=%s%%\n" "$tx" "$rx" "$loss"
      else
        loss="NA"
        printf "\033[1;31mfailed or zero counters\033[0m\n"
      fi

      echo "$name,$pps,$sz,${tx:-NA},${rx:-NA},$loss" >> "$CSV"
    done
  done
done

echo -e "\n\033[1;32mAll done.\033[0m  CSV written to: $CSV"
