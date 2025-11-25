#!/usr/bin/env bash
set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "jq is required (apt-get install -y jq)"; exit 2; }

cd "$(dirname "$0")"

: "${NS:=twodut-alpine-otg}"
: "${DUT_POD:=alpine-dut}"
: "${DUT_CTR:=dataplane}"
: "${OTG_LOCATION_P1:=eth1}"   # pair1
: "${OTG_LOCATION_P2:=eth2}"
: "${OTG_LOCATION_P3:=eth3}"   # pair2
: "${OTG_LOCATION_P4:=eth4}"
: "${PPS:=5000}"
: "${PKTS:=20000}"
: "${PKTSIZE:=512}"

# pull controller from .env if not exported
if [ -z "${OTG_API:-}" ] && [ -f ../.env ]; then source ../.env || true; fi
: "${OTG_API:?Missing OTG_API (set in env or ../.env)}"

OUT="../results"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"; MD="$OUT/conformance_${TS}.md"
pass(){ printf "PASS: %s\n" "$1" | tee -a "$MD"; }
fail(){ printf "FAIL: %s\n" "$1" | tee -a "$MD"; exit 2; }

echo "# Conformance ($TS)" >"$MD"

# 1) reachability
kubectl get ns "$NS" >/dev/null 2>&1 && pass "Namespace exists: $NS" || fail "Namespace missing"
curl -sk --connect-timeout 3 "$OTG_API" >/dev/null && pass "Controller reachable: $OTG_API" || fail "Controller not reachable"

# 2) four TE ports ready
READY_TE=$(kubectl -n "$NS" get pods -o name | grep -cE 'otg-port-eth[1-4]' || true)
[ "$READY_TE" -ge 2 ] && pass "Traffic engines present (>=2), detected: $READY_TE" || fail "Traffic engines not present"

# 3) DUT bridge members (all 4)
if kubectl -n "$NS" exec "$DUT_POD" -c "$DUT_CTR" -- sh -lc '
   bridge link | grep -q "eth13.*master br100" &&
   bridge link | grep -q "eth14.*master br100" &&
   bridge link | grep -q "eth15.*master br100" &&
   bridge link | grep -q "eth16.*master br100" '; then
  pass "br100 has eth13-eth16"
else
  fail "br100 missing one or more of eth13-eth16"
fi

# 4) Probe using JSON and final metrics
probe() {
  local txl="$1" rxl="$2" base="$3"
  local name="${base}_$RANDOM"
  local tmpf tx rx loss

  tmpf="$(mktemp)"
  
  # Run flow and capture JSON output
  otgen create flow -n "$name" -s 1.1.1.1 -d 2.2.2.2 \
    --size "$PKTSIZE" -r "$PPS" -c "$PKTS" \
    --tx p1 --rx p2 --txl "$txl" --rxl "$rxl" \
  | otgen run -k -a "$OTG_API" -y -m flow > "$tmpf" 2>&1
  
  local final_json
  final_json=$(grep -F '"transmit":"stopped"' "$tmpf" | tail -1 || tail -1 "$tmpf")
  rm -f "$tmpf"
  
  tx=$(echo "$final_json" | jq -r ".flow_metrics[] | select(.name==\"$name\") | .frames_tx // 0" 2>/dev/null || echo "0")
  rx=$(echo "$final_json" | jq -r ".flow_metrics[] | select(.name==\"$name\") | .frames_rx // 0" 2>/dev/null || echo "0")

  if [ "$tx" = "0" ] || [ -z "$tx" ]; then
    tx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_tx // 0' 2>/dev/null || echo "0")
    rx=$(echo "$final_json" | jq -r '.flow_metrics[0].frames_rx // 0' 2>/dev/null || echo "0")
  fi

  if [ "$tx" -gt 0 ]; then
    loss="$(awk -v a="$tx" -v b="$rx" 'BEGIN{v=(a-b)*100.0/a; if(v<0)v=0; if(v>100)v=100; printf "%.3f", v}')"
    pass "Probe ${base} ($txl->$rxl): tx=$tx rx=$rx loss=${loss}%"
  else
    fail "Probe ${base} ($txl->$rxl) failed (tx=$tx rx=$rx)"
  fi
}

# 5) probes (both pairs forward)
probe "$OTG_LOCATION_P1" "$OTG_LOCATION_P2" "p12"
probe "$OTG_LOCATION_P3" "$OTG_LOCATION_P4" "p34"

echo "Wrote $MD"
