#!/usr/bin/env bash
set -euo pipefail

# --- Settings ---
NS=${NS:-twodut-alpine-otg}

# Find the topology textproto (if changed, modify with new file name)
CANDIDATES=(
  "$HOME/kne/twodut-alpine-otg.textproto"
  "$(dirname "$0")/../twodut-alpine-otg.textproto"
  "$(dirname "$0")/twodut-alpine-otg.textproto"
)
PB=""
for p in "${CANDIDATES[@]}"; do
  [[ -f "$p" ]] && PB="$p" && break
done
[[ -n "$PB" ]] || { echo "ERROR: topology PB not found. Place twodut-alpine-otg.textproto under repo root."; exit 1; }

echo "== [1/6] (Re)create topology =="
if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  kne create "$PB"
else
  echo "Namespace $NS exists; skipping kne create."
fi

echo "== [2/6] Wait for controller & engines =="
CTRL_POD="$(kubectl -n "$NS" get pods -o name | grep -m1 otg-controller || true)"
[[ -n "$CTRL_POD" ]] || { echo "ERROR: controller pod not found in $NS"; exit 1; }
kubectl -n "$NS" wait --for=condition=Ready "$CTRL_POD" --timeout=300s
kubectl -n "$NS" wait --for=condition=Ready pod --all --timeout=300s

echo "== [3/6] Wire L2 inside DUT dataplane (br100 with eth13..eth16 + STP) =="
kubectl -n "$NS" exec alpine-dut -c dataplane -- sh -lc '
  set -e
  command -v ip >/dev/null || (apk update && apk add --no-cache iproute2)
  ip link show br100 >/dev/null 2>&1 || ip link add br100 type bridge
  ip link set br100 up
  for p in eth13 eth14 eth15 eth16; do
    ip link set "$p" up || true
    ip link set "$p" master br100 || true
  done
  # Enable STP to prevent loops
  ip link set br100 type bridge stp_state 1
  echo "[DUT bridge] members:"
  bridge link | grep -E "(eth13|eth14|eth15|eth16).*master br100" || true
  echo "[DUT bridge] STP enabled"
'

echo "== [4/6] Wire L2 inside CTL dataplane (br100 with eth13..eth16 + STP) =="
kubectl -n "$NS" exec alpine-ctl -c dataplane -- sh -lc '
  set -e
  command -v ip >/dev/null || (apk update && apk add --no-cache iproute2)
  ip link show br100 >/dev/null 2>&1 || ip link add br100 type bridge
  ip link set br100 up
  for p in eth13 eth14 eth15 eth16; do
    ip link set "$p" up || true
    ip link set "$p" master br100 || true
  done
  # Enable STP to prevent loops
  ip link set br100 type bridge stp_state 1
  echo "[CTL bridge] members:"
  bridge link | grep -E "(eth13|eth14|eth15|eth16).*master br100" || true
  echo "[CTL bridge] STP enabled"
'

echo "== [5/6] Discover controller API and write .env =="
CTRL_LB_IP="$(kubectl -n "$NS" get svc service-https-otg-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
[[ -n "$CTRL_LB_IP" ]] || { echo "ERROR: service-https-otg-controller has no external IP yet."; exit 1; }

mkdir -p "$(dirname "$0")/../"
ENVFILE="$(dirname "$0")/../.env"
cat > "$ENVFILE" <<EOF
export OTG_API="https://${CTRL_LB_IP}:8443"
export OTG_LOCATION_P1="eth1"
export OTG_LOCATION_P2="eth2"
export OTG_LOCATION_P3="eth3"
export OTG_LOCATION_P4="eth4"
EOF
source "$ENVFILE"
echo "Wrote $ENVFILE"
echo "OTG_API=$OTG_API"
echo ">> Run:  source ../.env   # refresh OTG_API in your shell"

echo "== [6/6] Sanity: controller answers =="
curl -sk "$OTG_API" >/dev/null || { echo "ERROR: controller not answering at $OTG_API"; exit 1; }
echo "Reset complete. STP enabled on both bridges to prevent traffic loops."
