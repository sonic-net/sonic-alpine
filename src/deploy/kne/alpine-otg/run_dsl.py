#!/usr/bin/env python3
# run_dsl.py — run tests from a YAML/JSON DSL and produce a bench_* CSV + report
import os, sys, json, subprocess, shlex, time, tempfile

USAGE = f"""Usage:
  ./run_dsl.py path/to/tests.yaml
  ./run_dsl.py path/to/tests.json
"""

def _read_yaml_min(src: str):
    """
    Minimal YAML reader for simple key/value, dicts, and list-of-scalars.
    """
    try:
        import yaml  # type: ignore
        with open(src, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except Exception:
        pass
    data = {}
    stack = [(0, data)]
    with open(src, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            indent = len(line) - len(line.lstrip(' '))
            while stack and indent < stack[-1][0]:
                stack.pop()
            cur = stack[-1][1]
            if line.lstrip().startswith('- '):
                # list item
                item = line.lstrip()[2:].strip()
                if not isinstance(cur, list):
                    # create a list under previous key if needed
                    if isinstance(cur, dict):
                        # last inserted key?
                        # minimal: look back; if none, fail
                        raise ValueError("Minimal YAML: list must follow a key")
                    else:
                        raise ValueError("Minimal YAML structure error")
                cur.append(_coerce(item))
            else:
                if ':' not in line:
                    raise ValueError("Minimal YAML expects 'key: value'")
                key, val = line.lstrip().split(':', 1)
                key = key.strip()
                val = val.strip()
                if not val:
                    # a nested mapping or list follows
                    nxt = {}
                    if isinstance(cur, dict):
                        cur[key] = nxt
                    else:
                        raise ValueError("Minimal YAML: nested value under non-dict")
                    stack.append((indent+2, nxt))
                else:
                    if isinstance(cur, dict):
                        cur[key] = _coerce(val)
                    else:
                        raise ValueError("Minimal YAML: key under non-dict")
    return data

def _coerce(s: str):
    if s.lower() in ('true','false'):
        return s.lower() == 'true'
    if s.lower() in ('null','none'):
        return None
    try:
        if s.isdigit() or (s.startswith('-') and s[1:].isdigit()):
            return int(s)
        # float?
        return float(s)
    except Exception:
        return s

def load_spec(path: str):
    if not os.path.isfile(path):
        sys.exit(f"DSL file not found: {path}")
    ext = os.path.splitext(path)[1].lower()
    if ext in ('.json',):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    if ext in ('.yaml', '.yml'):
        return _read_yaml_min(path)
    sys.exit("Unsupported DSL format (use .yaml/.yml or .json)")

def sh(cmd: str, env=None, check=True, capture=False):
    if capture:
        return subprocess.run(cmd, shell=True, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=check)
    else:
        return subprocess.run(cmd, shell=True, env=env, check=check)

def parse_table_for_counters(txt: str):
    p1tx=p1rx=p2tx=p2rx=0
    for line in txt.splitlines():
        parts = [p.strip() for p in line.split('|')]
        if len(parts) < 5: 
            continue
        name, tx, rx = parts[1], parts[2], parts[3]
        if name == 'p1':
            p1tx = int(tx) if tx.isdigit() else 0
            p1rx = int(rx) if rx.isdigit() else 0
        elif name == 'p2':
            p2tx = int(tx) if tx.isdigit() else 0
            p2rx = int(rx) if rx.isdigit() else 0
    return p1tx, p1rx, p2tx, p2rx

def loss_pct(p1tx, p2rx):
    if p1tx > 0:
        return round((p1tx - p2rx) * 100.0 / p1tx, 3)
    return 'NA'

def main():
    if len(sys.argv) != 2:
        sys.exit(USAGE)
    spec = load_spec(sys.argv[1])

    defaults = spec.get('defaults', {})
    scenarios = spec.get('scenarios', [])
    if not isinstance(scenarios, list) or not scenarios:
        sys.exit("No scenarios in DSL file")

    PPS      = str(defaults.get('pps', 20000))
    SIZE     = str(defaults.get('pktsize', 512))
    COUNT    = str(defaults.get('count', 50000))
    BIDIR    = bool(defaults.get('bidir', False))
    NS       = str(defaults.get('ns', os.environ.get('NS','twodut-alpine-otg')))
    CTRL     = str(defaults.get('controller', os.environ.get('OTG_API','')))
    if not CTRL and os.path.exists('../.env'):
        for line in open('../.env', 'r', encoding='utf-8'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # support: OTG_API=...   and   export OTG_API="..."
            if 'OTG_API' in line:
                # strip leading 'export ' if present
                if line.startswith('export '):
                    line = line[len('export '):]
                if line.startswith('OTG_API='):
                    CTRL = line.split('=',1)[1].strip().strip('"').strip("'")
                    if CTRL:
                        break
    if not CTRL:
        sys.exit("No controller specified (defaults.controller or env OTG_API)")

    imp_def = defaults.get('impair', {})
    IMP_EN  = bool(imp_def.get('enabled', False))
    IMP_LOSS = str(imp_def.get('loss', 1))
    IMP_DELAY = str(imp_def.get('delay', '10ms'))
    IMP_JITTER = str(imp_def.get('jitter', '2ms'))

    outdir = '../results/runs'
    os.makedirs(outdir, exist_ok=True)
    ts = time.strftime('%Y%m%d_%H%M%S')
    csv_path = os.path.join(outdir, f'bench_dsl_{ts}.csv')

    with open(csv_path, 'w', encoding='utf-8') as f:
        f.write('ns,api,pair,name,pps,pktsize,p1_tx,p1_rx,p2_tx,p2_rx,loss_pct\n')

    for sc in scenarios:
        name = sc.get('name', 'unnamed')
        ports = sc.get('ports', [])
        if not isinstance(ports, list) or len(ports) != 2:
            sys.exit(f"Scenario '{name}': 'ports' must be a 2-item list, got {ports}")
        p1, p2 = str(ports[0]), str(ports[1])

        pps   = str(sc.get('pps', PPS))
        size  = str(sc.get('pktsize', SIZE))
        count = str(sc.get('count', COUNT))
        bidir = bool(sc.get('bidir', BIDIR))
        ctrl  = str(sc.get('controller', CTRL))

        imp = sc.get('impair', {})
        use_imp = bool(imp.get('enabled', IMP_EN))
        loss = str(imp.get('loss', IMP_LOSS))
        delay = str(imp.get('delay', IMP_DELAY))
        jitter = str(imp.get('jitter', IMP_JITTER))

        print(f"\n[DSL] Scenario: {name}  ports={p1}->{p2}  pps={pps} size={size} count={count} bidir={bidir} impair={use_imp}")
        if use_imp:
            env = os.environ.copy()
            env.update({'NS': NS, 'IMP_LOSS': loss, 'IMP_DELAY': delay, 'IMP_JITTER': jitter})
            sh('./impair_on.sh', env=env, check=True)

        tmp = tempfile.NamedTemporaryFile(delete=False); tmp.close()
        cmd = (
            "otgen create flow -n {name} -s 1.1.1.1 -d 2.2.2.2 --size {size} -r {pps} -c {cnt} "
            "--tx p1 --rx p2 --txl {p1} --rxl {p2} "
            "| otgen run -k -a {api} -y -m port "
            "| otgen transform -m port "
            "| TERM=dumb env TERM=dumb timeout 6s otgen display --mode table > {out}"
        ).format(name=shlex.quote(name+'_fwd'), size=size, pps=pps, cnt=count, p1=p1, p2=p2, api=ctrl, out=tmp.name)
        sh(cmd, check=True)
        table = open(tmp.name, 'r', encoding='utf-8').read()
        p1tx,p1rx,p2tx,p2rx = parse_table_for_counters(table)
        with open(csv_path, 'a', encoding='utf-8') as f:
            f.write(f"{NS},{ctrl},{p1}-{p2},{name}_fwd,{pps},{size},{p1tx},{p1rx},{p2tx},{p2rx},{loss_pct(p1tx,p2rx)}\n")
        time.sleep(2)
        os.unlink(tmp.name)

        if bidir:
            tmp = tempfile.NamedTemporaryFile(delete=False); tmp.close()
            cmd = (
                "otgen create flow -n {name} -s 2.2.2.2 -d 1.1.1.1 --size {size} -r {pps} -c {cnt} "
                "--tx p1 --rx p2 --txl {rp1} --rxl {rp2} "
                "| otgen run -k -a {api} -y -m port "
                "| otgen transform -m port "
                "| TERM=dumb env TERM=dumb timeout 6s otgen display --mode table > {out}"
            ).format(name=shlex.quote(name+'_rev'), size=size, pps=pps, cnt=count, rp1=p2, rp2=p1, api=ctrl, out=tmp.name)
            sh(cmd, check=True)
            table = open(tmp.name, 'r', encoding='utf-8').read()
            p1tx,p1rx,p2tx,p2rx = parse_table_for_counters(table)
            with open(csv_path, 'a', encoding='utf-8') as f:
                f.write(f"{NS},{ctrl},{p2}-{p1},{name}_rev,{pps},{size},{p1tx},{p1rx},{p2tx},{p2rx},{loss_pct(p1tx,p2rx)}\n")
            time.sleep(2)
            os.unlink(tmp.name)

        if use_imp:
            sh('./impair_off.sh', check=True)

    print(f"\n[DSL] Wrote CSV: {csv_path}")
    sh('./report.sh', check=True)
    print("[DSL] Report generated (latest in results/).")

if __name__ == '__main__':
    main()

