#!/usr/bin/env bash
# doctor.sh — preflight health checks (controller, pods, ports, wiring, probe flows)
set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "jq is required (apt-get install -y jq)"; exit 2; }
cd "$(dirname "$0")"

# --- Config (override via env) ---
: "${NS:=twodut-alpine-otg}"
: "${DUT_POD:=alpine-dut}"
: "${DUT_CTR:=dataplane}"
: "${CTL_POD:=alpine-ctl}"
: "${CTL_CTR:=dataplane}"
: "${BRIDGE:=br100}"
: "${EDGE_PORTS:=eth13 eth14 eth15 eth16}"
: "${OTG_LOCATION_P1:=eth1}"
: "${OTG_LOCATION_P2:=eth2}"
: "${OTG_LOCATION_P3:=eth3}"
: "${OTG_LOCATION_P4:=eth4}"
: "${PPS:=2000}"
: "${PKTS:=5000}"
: "${PKTSIZE:=512}"

# Pull controller from ../.env if not exported
if [ -z "${OTG_API:-}" ] && [ -f ../.env ]; then
  source ../.env || true
fi
: "${OTG_API:?Missing OTG_API (set in env or ../.env)}"

OUT="../results"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
MD="$OUT/configuration_${TS}.md"

pass(){ echo "PASS: $1" | tee -a /dev/stderr; printf "✅ %s\n" "$1" >>"$MD"; }
fail(){ echo "FAIL: $1" | tee -a /dev/stderr; printf "❌ %s\n" "$1" >>"$MD"; exit 2; }
warn(){ echo "WARN: $1" | tee -a /dev/stderr; printf "⚠️ %s\n" "$1" >>"$MD"; }

echo "# Configuration (preflight) — $TS" >"$MD"
echo "- Namespace: \`$NS\`" >>"$MD"
echo "- Controller: \`$OTG_API\`" >>"$MD"
echo "- Ports: \`$OTG_LOCATION_P1\`↔\`$OTG_LOCATION_P2\`, \`$OTG_LOCATION_P3\`↔\`$OTG_LOCATION_P4\`" >>"$MD"
echo >>"$MD"

# Create/repair $BRIDGE and add $EDGE_PORTS
wire_br() {
  local pod="$1" ctr="$2"
  kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc '
    set -e
    command -v bridge >/dev/null 2>&1 || (apk update >/dev/null && apk add --no-cache iproute2 >/dev/null)
    ip link show '"$BRIDGE"' >/dev/null 2>&1 || ip link add '"$BRIDGE"' type bridge
    for p in '"$EDGE_PORTS"'; do
      ip link set "$p" up 2>/dev/null || true
      ip link set "$p" master '"$BRIDGE"' 2>/dev/null || true
    done
    ip link set '"$BRIDGE"' up
  '
}

# Verify all $EDGE_PORTS are part of $BRIDGE on a pod
check_br() {
  local pod="$1" ctr="$2"
  kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc '
    ok=1
    for p in '"$EDGE_PORTS"'; do
      bridge link | grep -E -q "$p.*master '"$BRIDGE"'" || { echo "missing: $p"; ok=0; }
    done
    exit $((ok?0:1))
  '
}

# 1) Namespace present
kubectl get ns "$NS" >/dev/null 2>&1 && pass "Kubernetes namespace exists: $NS" || fail "Namespace missing: $NS"

# 2) Controller Service present
if kubectl -n "$NS" get svc service-https-otg-controller >/dev/null 2>&1; then
  pass "Controller Service present in $NS"
else
  warn "Controller Service not found (service-https-otg-controller). Continuing."
fi

# 3) Controller HTTPS reachable
if curl -sk --connect-timeout 3 "$OTG_API" >/dev/null; then
  pass "Controller reachable at $OTG_API"
else
  fail "Controller not reachable at $OTG_API (check port/IP/ingress)"
fi

# 4) Traffic Engine pods ready (at least 2 containers Ready)
read -r ready total <<<"$(kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{"\n"}{end}' \
  | awk '{for(i=1;i<=NF;i++) if($i=="true") r++; t++} END{print (r+0),(t+0)}')"
if [ "${total:-0}" -eq 0 ]; then
  warn "No pods returned in namespace (did you deploy KNE + ixia-c?)"
else
  [ "$ready" -ge 2 ] && pass "At least two containers are Ready ($ready/$total)" \
                     || fail "Insufficient Ready containers ($ready/$total)"
fi

# 5) Ensure L2 wiring on BOTH switches (create/repair + verify)
wire_br "$DUT_POD" "$DUT_CTR"
wire_br "$CTL_POD" "$CTL_CTR"

check_br "$DUT_POD" "$DUT_CTR" && pass "DUT $BRIDGE has $EDGE_PORTS" \
                                 || fail "DUT $BRIDGE missing one or more of: $EDGE_PORTS"
check_br "$CTL_POD" "$CTL_CTR" && pass "CTL $BRIDGE has $EDGE_PORTS" \
                                 || fail "CTL $BRIDGE missing one or more of: $EDGE_PORTS"


# 6) Probe helper — run one flow and read final totals from the stream
probe_pair() {
  local txl="$1" rxl="$2" base="$3"
  local name="${base}_$RANDOM"   # unique per run
  local tx rx loss

  read tx rx < <(
    otgen create flow -n "$name" -s 1.1.1.1 -d 2.2.2.2 \
      --size "${PKTSIZE:-512}" -r "${PPS:-5000}" -c "${PKTS:-20000}" \
      --tx p1 --rx p2 --txl "$txl" --rxl "$rxl" \
    | otgen run -k -a "$OTG_API" -y -m flow \
    | tail -1 \
    | jq -r '.flow_metrics[0] | "\(.frames_tx) \(.frames_rx)"'
  )

  tx=${tx:-0}; rx=${rx:-0}
  if [ "$tx" -gt 0 ]; then
    loss="$(awk -v a="$tx" -v b="$rx" 'BEGIN{v=(a-b)*100.0/a; if(v<0)v=0; if(v>100)v=100; printf "%.3f", v}')"
    pass "Probe ${base} ($txl→$rxl): tx=$tx rx=$rx loss=${loss}%"
  else
    fail "Probe ${base} ($txl→$rxl) produced no TX (tx=$tx rx=$rx)"
  fi
}



# 7) Probes on both pairs (forward)
probe_pair "$OTG_LOCATION_P1" "$OTG_LOCATION_P2" "p12"
probe_pair "$OTG_LOCATION_P3" "$OTG_LOCATION_P4" "p34"

echo >>"$MD"
echo "All checks completed. Wrote $MD"
