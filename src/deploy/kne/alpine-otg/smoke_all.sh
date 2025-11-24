#!/usr/bin/env bash
# smoke_all.sh - full-stack run to test EVERYTHING end-to-end
set -euo pipefail
cd "$(dirname "$0")"

# ---- knobs ----
: "${NS:=twodut-alpine-otg}"          # k8s namespace (if used in your helpers)
: "${PPS:=20000}"                     # packets per second per flow
: "${SIZE:=512}"                      # packet size (bytes)
: "${PKTS:=10000}"                    # total packets per flow (reduced for speed)
: "${CONC:=2}"                        # concurrent flows per direction
: "${PORT_PAIRS:=eth1,eth2;eth3,eth4}"# "tx,rx;tx,rx" for scale_matrix.sh
: "${BIDIR:=1}"                       # 1 = bidirectional flows

# Impairment defaults (A/B)
: "${IMP_LOSS:=0.5}"                  # percent
: "${IMP_DELAY:=5ms}"
: "${IMP_JITTER:=1ms}"
: "${IFACES:=eth13 eth14 eth15 eth16}" # host ifaces used by your impair scripts

: "${NL_PLAN:=baseline on eth1,eth2 at 20kpps size 512 bidir; on eth3,eth4 256B 15kpps bidir; impaired on eth1,eth2 loss 0.5% delay 5ms bidir at 40kpps}"

OUT="../results"
mkdir -p "$OUT" "$OUT/runs"

banner(){ echo; echo "======== $* ========"; echo; }

# 1) Reset cluster (rebuild clean state and write .env)
banner "1) Reset & write .env (with STP enabled)"
./reset_cluster.sh

# 2) Ensure current shell has fresh env (OTG_API, port locations)
if [[ -f ../.env ]]; then
  # shellcheck disable=SC1091
  source ../.env
  echo "OTG_API=${OTG_API:-<not-set>}"
  # Export all 4 port locations for dual-device testing
  export OTG_LOCATION_P1 OTG_LOCATION_P2 OTG_LOCATION_P3 OTG_LOCATION_P4
else
  echo "WARN: ../.env not found - configuration.sh may discover API dynamically."
fi

# 3) Preflight health checks
banner "2) Configuration (preflight)"
./configuration.sh

# 4) Minimal conformance probes (OpenConfig feature/profile checks)
banner "3) Conformance (wires + probes on both pairs)"
./conformance.sh

# 5) Baseline traffic + report
banner "4) Baseline bench + report (both pairs)"
PKTS="$PKTS" ./bench.sh
./report.sh

# 6) Scale-out (both pairs, bidir) + report
banner "5) Scale-out (matrix across both pairs, bidir) + report"
PORT_PAIRS="$PORT_PAIRS" BIDIR="$BIDIR" PPS="$PPS" SIZE="$SIZE" PKTS="$PKTS" CONC="$CONC" \
  ./scale_matrix.sh
./report.sh

# 7) NL mini-DSL run (intent -> YAML -> run -> report)
banner "6) Mini-DSL run + report"
if [[ -n "${NL_PLAN}" ]]; then
  python3 ./nl_run.py "$NL_PLAN"
else
  python3 ./nl_run.py
fi

# 8) Impairment A/B across BOTH pairs then restore, with compare summary
banner "7) Impairment A/B across BOTH pairs (+ restore)"
IFACES="$IFACES" IMP_LOSS="$IMP_LOSS" IMP_DELAY="$IMP_DELAY" IMP_JITTER="$IMP_JITTER" \
  SKIP_BASELINE=1 ./compare.sh

# 9) Artifact roll-up
banner "8) Artifact summary"
echo "Latest report:      $(ls -1t "$OUT"/report_*.md 2>/dev/null | head -n1 || echo 'none')"
echo "Latest CSV:         $(ls -1t "$OUT"/runs/*.csv 2>/dev/null | head -n1 || echo 'none')"
echo "Configuration output: $(ls -1t "$OUT"/configuration_*.md 2>/dev/null | head -n1 || echo 'none')"
echo "Conformance output: $(ls -1t "$OUT"/conformance_*.md 2>/dev/null | head -n1 || echo 'none')"
echo "A/B before:         $(ls -1t "$OUT"/report_before_*.md 2>/dev/null | head -n1 || echo 'none')"
echo "A/B after:          $(ls -1t "$OUT"/report_after_*.md 2>/dev/null | head -n1 || echo 'none')"
echo "Compare summary:    $(ls -1t "$OUT"/compare_*.md 2>/dev/null | head -n1 || echo 'none')"

banner "Done! Open the newest report_* in results/ (charts included)"
