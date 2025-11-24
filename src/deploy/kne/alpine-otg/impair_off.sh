#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${NS:=twodut-alpine-otg}"
: "${DUT_POD:=alpine-dut}"
: "${CTL_POD:=alpine-ctl}"
: "${DUT_CTR:=dataplane}"
: "${CTL_CTR:=dataplane}"
: "${IFACES:=eth13 eth14 eth15 eth16}"
: "${IMPAIR_BOTH:=1}"  # Set to 0 to only clear DUT

echo "[impair_off] IFACES=[$IFACES]"

clear_impair() {
  local pod="$1" ctr="$2" label="$3"
  echo "[impair_off] Clearing from $label ($pod)"
  
  for ifc in $IFACES; do
    kubectl -n "$NS" exec "$pod" -c "$ctr" -- sh -lc "
      tc qdisc del dev $ifc root 2>/dev/null || true
      echo \"  [$label/$ifc] \$(tc qdisc show dev $ifc | head -1 || true)\"
    "
  done
}

# Clear from DUT (alpine-dut)
clear_impair "$DUT_POD" "$DUT_CTR" "DUT"

# Clear from CTL (alpine-ctl)
if [[ "${IMPAIR_BOTH}" == "1" ]]; then
  clear_impair "$CTL_POD" "$CTL_CTR" "CTL"
else
  echo "[impair_off] Skipping CTL (IMPAIR_BOTH=0)"
fi

echo "[impair_off] Cleared."
