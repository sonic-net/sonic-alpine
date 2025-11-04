#!/usr/bin/env bash
# scale_matrix.sh - multi-port / multi-node scaler 
set -euo pipefail
cd "$(dirname "$0")"

: "${NS:=default}"
: "${PPS:=10000}"
: "${SIZE:=512}"
: "${PKTS:=10000}"
: "${CONC:=2}"
: "${PORT_PAIRS:=eth1,eth2}"
: "${APIS:=}"
: "${BIDIR:=0}"

command -v jq >/dev/null || { echo "ERROR: jq is required." >&2; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="../results/runs"
mkdir -p "$OUTDIR"
OUTCSV="${OUTCSV:-$OUTDIR/scale_${TS}.csv}"

echo "ns,api,pair,name,pps,pktsize,p1_tx,p1_rx,p2_tx,p2_rx,loss_pct" > "$OUTCSV"

run_one() {
  local api="$1" p1="$2" p2="$3" name="$4" pps="$5" size="$6" pkts="$7" tmp="$8"
  otgen create flow -n "$name" -s 1.1.1.1 -d 2.2.2.2 --size "$size" -r "$pps" -c "$pkts" \
    --tx p1 --rx p2 \
    --txl "$p1" --rxl "$p2" \
  | otgen run -k -a "$api" -y -m flow > "$tmp" 2>&1
}

parse_all() {
  local final_json
  final_json=$(grep -F '"transmit":"stopped"' "$1" | tail -1 || tail -1 "$1")
  
  local p1tx p1rx p2tx p2rx
  p1tx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_tx // 0' 2>/dev/null || echo "0")
  p1rx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_rx // 0' 2>/dev/null || echo "0")
  p2tx="0"
  p2rx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_rx // 0' 2>/dev/null || echo "0")
  
  echo "$p1tx $p1rx $p2tx $p2rx"
}

append_csv() {
  local api="$1" pair="$2" name="$3" pps="$4" size="$5" p1tx="$6" p1rx="$7" p2tx="$8" p2rx="$9"
  local loss="NA"
  if [[ "$p1tx" =~ ^[0-9]+$ && "$p1tx" -gt 0 ]]; then
    loss=$(awk -v a="$p1tx" -v b="$p2rx" 'BEGIN{printf "%.3f", (a-b)*100.0/a}')
  fi
  echo "$NS,$api,$pair,$name,$pps,$size,$p1tx,$p1rx,$p2tx,$p2rx,$loss" >> "$OUTCSV"
}

probe_api() {
  local api="$1"
  curl -sk --connect-timeout 2 "$api/config" >/dev/null 2>&1
}

# Discover/normalize controllers
apis=()
if [[ -n "$APIS" ]]; then
  IFS=';' read -r -a apis <<< "$APIS"
else
  source ../.env
  : "${OTG_API:?Missing OTG_API in .env or APIS env var}"
  apis=("$OTG_API")
fi

# Filter to reachable controllers
reachable=()
for a in "${apis[@]}"; do
  if probe_api "$a"; then
    reachable+=("$a")
  else
    echo "WARN: skipping unreachable controller: $a" >&2
  fi
done
apis=("${reachable[@]}")
if [[ ${#apis[@]} -eq 0 ]]; then
  echo "ERROR: no reachable controllers; aborting." >&2
  exit 2
fi

IFS=';' read -r -a pairs <<< "$PORT_PAIRS"

echo "APIs: ${apis[*]}"
echo "Pairs: ${pairs[*]}"
echo "Writing: $OUTCSV"
echo "BIDIR: $BIDIR, PPS: $PPS, SIZE: $SIZE, PKTS: $PKTS, CONC: $CONC"
echo

jid=0

for api in "${apis[@]}"; do
  for pair in "${pairs[@]}"; do
    IFS=',' read -r P1 P2 <<< "$pair"
    base="scale_${P1}_${P2}"

    (
      tmpf="$(mktemp)"; name="${base}_fwd"
      if run_one "$api" "$P1" "$P2" "$name" "$PPS" "$SIZE" "$PKTS" "$tmpf"; then
        read -r f_p1tx f_p1rx f_p2tx f_p2rx < <(parse_all "$tmpf")
        append_csv "$api" "$P1-$P2" "$name" "$PPS" "$SIZE" "$f_p1tx" "$f_p1rx" "$f_p2tx" "$f_p2rx"
        echo "[OK] $api $P1->$P2 $name  p1_tx=$f_p1tx p2_rx=$f_p2rx"
      else
        echo "[SKIP] $api $P1->$P2 $name (run failed)" >&2
      fi
      rm -f "$tmpf"
    ) &

    (( ++jid % CONC == 0 )) && wait

    if [[ "$BIDIR" -eq 1 ]]; then
      (
        tmpr="$(mktemp)"; name="${base}_rev"
        if run_one "$api" "$P2" "$P1" "$name" "$PPS" "$SIZE" "$PKTS" "$tmpr"; then
          read -r r_p1tx r_p1rx r_p2tx r_p2rx < <(parse_all "$tmpr")
          append_csv "$api" "$P2-$P1" "$name" "$PPS" "$SIZE" "$r_p1tx" "$r_p1rx" "$r_p2tx" "$r_p2rx"
          echo "[OK] $api $P2->$P1 $name  p1_tx=$r_p1tx p2_rx=$r_p2rx"
        else
          echo "[SKIP] $api $P2->$P1 $name (run failed)" >&2
        fi
        rm -f "$tmpr"
      ) &
      (( ++jid % CONC == 0 )) && wait
    fi

  done
done

wait
echo
echo "Done. CSV at: $OUTCSV"
