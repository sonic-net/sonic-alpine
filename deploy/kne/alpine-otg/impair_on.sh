#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

: "${NS:=twodut-alpine-otg}"
: "${DUT_POD:=alpine-dut}"
: "${CTL_POD:=alpine-ctl}"
: "${DUT_CTR:=dataplane}"
: "${CTL_CTR:=dataplane}"
: "${IMP_LOSS:=1}"           # % loss
: "${IMP_DELAY:=10ms}"
: "${IMP_JITTER:=2ms}"
: "${IFACES:=eth13 eth14 eth15 eth16}"
: "${IMPAIR_BOTH:=1}"  # Set to 0 to only impair DUT (for testing p12 only)

echo "[impair_on] NS=$NS IFACES=[$IFACES]  loss=${IMP_LOSS}% delay=${IMP_DELAY} jitter=${IMP_JITTER}"

apply_impair() {
  local pod="$1" ctr="$2" label="$3"
  echo "[impair_on] Applying to $label ($pod)"
  
  kubectl -n "$NS" get pod "$pod" >/dev/null
  kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc '
    command -v tc >/dev/null || (apk update && apk add --no-cache iproute2)
  ' >/dev/null
  
  for ifc in $IFACES; do
    kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc "
      set -e
      ip link set $ifc up || true
      tc qdisc replace dev $ifc root netem loss ${IMP_LOSS}% delay ${IMP_DELAY} ${IMP_JITTER} distribution normal
      echo \"  [$label/$ifc] \$(tc qdisc show dev $ifc | head -1)\"
    "
  done
}

# Apply to DUT (alpine-dut) - affects eth1→eth2 (p12)
apply_impair "$DUT_POD" "$DUT_CTR" "DUT"

# Apply to CTL (alpine-ctl) - affects eth3→eth4 (p34)
if [[ "${IMPAIR_BOTH}" == "1" ]]; then
  apply_impair "$CTL_POD" "$CTL_CTR" "CTL"
else
  echo "[impair_on] Skipping CTL (IMPAIR_BOTH=0)"
fi

echo "[impair_on] Applied."
