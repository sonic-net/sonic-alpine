#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

OUTDIR="../results"
RUNS_DIR="$OUTDIR/runs"
mkdir -p "$OUTDIR" "$RUNS_DIR" "$OUTDIR/charts"

# Pick the most recent CSV among bench_*, bench_dsl_*, scale_*
LATEST="$(ls -1t "$RUNS_DIR"/bench_*.csv "$RUNS_DIR"/bench_dsl_*.csv "$RUNS_DIR"/scale_*.csv 2>/dev/null | head -n1 || true)"
[ -n "$LATEST" ] || { echo "No CSV found in $RUNS_DIR"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
REPORT="$OUTDIR/report_${TS}.md"

# --- 1) Main report ---
python - "$LATEST" "$REPORT" <<'PY'
import csv, sys
csv_path, out_path = sys.argv[1], sys.argv[2]

rows = []
with open(csv_path, newline='') as f:
    r = csv.DictReader(f)
    for row in r:
        try:
            pps = int(row.get('pps') or 0)
            size = int(row.get('pktsize') or row.get('size') or 0)
            def to_int(x):
                try: return int(x)
                except: return None
            tx = row.get('tx_from_p1');  rx = row.get('rx_on_p2')
            if tx is None: tx = row.get('p1_tx')
            if rx is None: rx = row.get('p2_rx')
            tx_i, rx_i = to_int(tx), to_int(rx)
            lp = row.get('loss_pct')
            try: loss = float(lp) if lp not in (None,'NA','') else None
            except: loss = None
            rows.append({'name': row.get('name',''), 'pps': pps, 'pktsize': size, 'tx': tx_i, 'rx': rx_i, 'loss_pct': loss})
        except: pass

by_size = {}
for r in rows:
    by_size.setdefault(r['pktsize'], []).append(r)

def best_pps(group, thresh=0.1):
    ok = [g['pps'] for g in group if g['loss_pct'] is not None and g['loss_pct'] <= thresh]
    return max(ok) if ok else None

total = len(rows)
loss_values = [r['loss_pct'] for r in rows if r['loss_pct'] is not None]
avg_loss = round(sum(loss_values)/len(loss_values), 3) if loss_values else 0.0

lines = []
lines.append(f"# OTG Bench Report\n")
lines.append(f"**Source CSV:** `{csv_path}`\n")
lines.append("## Top takeaways\n")
lines.append(f"- Total runs: **{total}**, average loss across reported runs: **{avg_loss}%**")
for size in sorted(by_size):
    bp = best_pps(by_size[size])
    if bp:
        lines.append(f"- {size}B: highest pps with ≤0.1% loss → **{bp} pps**")
    else:
        lines.append(f"- {size}B: no run met ≤0.1% loss threshold")

lines.append("\n## Detailed results\n")
lines.append("| name | pps | pktsize | tx_from_p1 | rx_on_p2 | loss_pct |")
lines.append("|---|---:|---:|---:|---:|---:|")
for r in rows:
    tx = "NA" if r['tx'] is None else str(r['tx'])
    rx = "NA" if r['rx'] is None else str(r['rx'])
    lp = "NA" if r['loss_pct'] is None else f"{r['loss_pct']:.3f}"
    lines.append(f"| {r['name']} | {r['pps']} | {r['pktsize']} | {tx} | {rx} | {lp} |")

with open(out_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(out_path)
PY

# --- 2) ELI-OPS ---
python - "$LATEST" "$REPORT" <<'PY'
import csv, sys
csv_path, out_path = sys.argv[1], sys.argv[2]

rows=[]
with open(csv_path, newline='') as f:
    for r in csv.DictReader(f):
        try:
            r['pps']=int(r.get('pps') or 0)
            r['pktsize']=int(r.get('pktsize') or r.get('size') or 0)
            def to_i(x):
                try: return int(x)
                except: return None
            tx = r.get('tx_from_p1') or r.get('p1_tx')
            rx = r.get('rx_on_p2')  or r.get('p2_rx')
            r['tx']=to_i(tx); r['rx']=to_i(rx)
            r['loss']=None
            lp=r.get('loss_pct')
            if lp not in (None,'NA',''):
                try: r['loss']=float(lp)
                except: pass
            rows.append(r)
        except: pass

def worst_run(rs):
    rs=[x for x in rs if x['loss'] is not None]
    return max(rs, key=lambda x:x['loss']) if rs else None

def tips(w):
    out=[]
    if not w: return ["Traffic ran but loss data was not present."]
    if w['loss']>5:  out.append("Loss is very high. Check DUT br100 members and impairment settings.")
    elif w['loss']>1: out.append("Moderate loss. Verify OTG port locations and engine link states.")
    else:            out.append("Loss is low. Consider increasing pps or adding more port pairs.")
    out.append("If protocols are in use, confirm adjacencies before line-rate.")
    out.append("Capture a short pcap to localize drops.")
    return out

w=worst_run(rows)
with open(out_path,"a") as f:
    f.write("\n## Explain like I'm ops\n")
    if w:
        f.write(f"- Worst loss run: **{w.get('name','')}** ({w.get('pps',0)} pps, {w.get('pktsize',0)}B) → loss **{w['loss']:.2f}%**\n")
    else:
        f.write("- No loss figure available; verify controller metrics parsing.\n")
    for t in tips(w):
        f.write(f"- {t}\n")
PY

# --- 3) Charts ---
python - "$LATEST" "$REPORT" "$OUTDIR/charts" <<'PY'
import csv, sys, os
csv_path, out_path, chart_dir = sys.argv[1], sys.argv[2], sys.argv[3]

rows=[]
with open(csv_path, newline='') as f:
    r = csv.DictReader(f)
    for row in r:
        try:
            pps = int(row.get('pps') or 0)
            size = int(row.get('pktsize') or row.get('size') or 0)
            lp = row.get('loss_pct')
            loss = None
            if lp not in (None,'NA',''):
                try: loss = float(lp)
                except: pass
            rows.append({'pps':pps, 'pktsize':size, 'loss':loss})
        except: pass

if not rows:
    sys.exit(0)

# Group by size
by_size={}
for x in rows:
    by_size.setdefault(x['pktsize'], []).append(x)

# Chart 1: Loss vs PPS
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fig1 = plt.figure()
for size in sorted(by_size):
    xs=[r['pps'] for r in by_size[size] if r['loss'] is not None]
    ys=[r['loss'] for r in by_size[size] if r['loss'] is not None]
    if xs and ys:
        plt.plot(xs, ys, marker='o', label=f"{size}B")
plt.xlabel("pps")
plt.ylabel("loss %")
plt.title("Loss vs PPS (by packet size)")
plt.legend()
loss_fn = os.path.join(chart_dir, "loss_vs_pps.png")
fig1.savefig(loss_fn, bbox_inches='tight')

# Chart 2: Best safe PPS (<=0.1% loss)
safe={}
for size in by_size:
    ok=[r['pps'] for r in by_size[size] if r['loss'] is not None and r['loss']<=0.1]
    safe[size]=max(ok) if ok else 0

fig2 = plt.figure()
labels=sorted(safe)
vals=[safe[k] for k in labels]
plt.bar([str(k) for k in labels], vals)
plt.xlabel("packet size (B)")
plt.ylabel("pps")
plt.title("Best safe PPS (≤0.1% loss)")
best_fn = os.path.join(chart_dir, "best_safe_pps.png")
fig2.savefig(best_fn, bbox_inches='tight')

with open(out_path, "a") as f:
    f.write("\n## Charts\n")
    f.write("![Loss vs PPS](charts/loss_vs_pps.png)\n\n")
    f.write("![Best safe PPS](charts/best_safe_pps.png)\n")
PY

echo "Wrote $REPORT"
