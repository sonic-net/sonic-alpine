#!/usr/bin/env bash
# A/B compare: baseline -> impair -> re-run -> restore
# Uses existing bench.sh + report.sh in this folder.
# Set SKIP_BASELINE=1 to reuse existing baseline (avoid redundant bench run)
set -euo pipefail
cd "$(dirname "$0")"

OUTDIR="../results"
RUNS_DIR="$OUTDIR/runs"
mkdir -p "$RUNS_DIR"

latest_report() { ls -1t "$OUTDIR"/report_*.md 2>/dev/null | head -n1 || true; }
latest_bench()  { ls -1t "$RUNS_DIR"/bench_*.csv 2>/dev/null | head -n1 || true; }

TS="$(date +%Y%m%d_%H%M%S)"
CMP_MD="$OUTDIR/compare_${TS}.md"

# Check if we should skip baseline (already done by caller)
if [[ "${SKIP_BASELINE:-0}" == "1" ]]; then
  echo "[compare] === USING EXISTING BASELINE (SKIP_BASELINE=1) ==="
  BASE_RPT="$(latest_report)"
  BASE_CSV="$(latest_bench)"
  if [[ -z "$BASE_RPT" || -z "$BASE_CSV" ]]; then
    echo "ERROR: SKIP_BASELINE=1 but no existing report/CSV found!"
    echo "Run ./bench.sh and ./report.sh first, or unset SKIP_BASELINE"
    exit 1
  fi
  cp -f "$BASE_RPT" "$OUTDIR/report_before_${TS}.md"
else
  echo "[compare] === BASELINE ==="
  ./bench.sh
  ./report.sh
  BASE_RPT="$(latest_report)"
  BASE_CSV="$(latest_bench)"
  cp -f "$BASE_RPT" "$OUTDIR/report_before_${TS}.md"
fi

echo "[compare] === IMPAIR ON ==="
# Tune via env: IMP_LOSS, IMP_DELAY, IMP_JITTER, IFACE_A/B, NS, DUT_POD, DUT_CTR
IFACES="${IFACES:-eth13 eth14 eth15 eth16}" IMP_LOSS="${IMP_LOSS:-1}" IMP_DELAY="${IMP_DELAY:-10ms}" IMP_JITTER="${IMP_JITTER:-2ms}" ./impair_on.sh

./bench.sh
./report.sh
IMP_RPT="$(latest_report)"
IMP_CSV="$(latest_bench)"
cp -f "$IMP_RPT" "$OUTDIR/report_after_${TS}.md"

echo "[compare] === IMPAIR OFF (restore) ==="
IFACES="${IFACES:-eth13 eth14 eth15 eth16}" ./impair_off.sh

echo "[compare] Writing summary: $CMP_MD"
{
  echo "# A/B Compare (${TS})"
  echo
  echo "## Inputs"
  echo "- Baseline CSV: \`$(basename "$BASE_CSV")\`"
  echo "- Impaired CSV: \`$(basename "$IMP_CSV")\`"
  echo "- Baseline report: \`$(basename "$BASE_RPT")\` -> saved as \`report_before_${TS}.md\`"
  echo "- Impaired report: \`$(basename "$IMP_RPT")\` -> saved as \`report_after_${TS}.md\`"
  echo
  echo "## Quick tips"
  echo "- Expect higher loss and/or lower goodput in impaired run."
  echo "- If loss unchanged, verify \`tc qdisc show\` on DUT and confirm flow path uses the impaired interfaces."
} >"$CMP_MD"

echo "[compare] Done."
