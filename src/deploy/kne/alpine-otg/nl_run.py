#!/usr/bin/env python3
import os, re, sys, time, subprocess, shlex, tempfile, textwrap, json

USAGE = """\
Examples:
  ./nl_run.py "baseline on eth1,eth2 bidir at 20kpps size 512 count 50000;
               impaired on eth1,eth2 loss 0.5% delay 5ms jitter 1ms bidir at 40kpps;
               on eth3,eth4 256B 15kpps bidir count 50000"

Notes: separate scenarios with ';' and include 'impaired' (or 'loss xx%') to turn impairment on.
"""

def kpps_to_int(s):
    m=re.search(r'(\d+(\.\d+)?)\s*kpps', s)
    if m: return int(float(m.group(1))*1000)
    m=re.search(r'\b(\d+)\s*pps\b', s)
    return int(m.group(1)) if m else None

def pktsize(s):
    m=re.search(r'(?:size|pktsize|packet size)\s*(\d+)', s); 
    if m: return int(m.group(1))
    m=re.search(r'\b(\d+)\s*B\b', s)
    return int(m.group(1)) if m else None

def count_pkts(s):
    m=re.search(r'count\s*(\d+)', s); 
    if m: return int(m.group(1))
    m=re.search(r'\b(\d+)\s*(?:pkts|packets)\b', s)
    return int(m.group(1)) if m else None

def ports(s):
    m=re.search(r'eth(\d)\s*[,/ -]\s*eth(\d)', s)
    return (f"eth{m.group(1)}", f"eth{m.group(2)}") if m else None

def loss(s):
    m=re.search(r'loss\s*([\d.]+)\s*%', s); 
    return float(m.group(1)) if m else None

def delay(s):
    m=re.search(r'delay\s*([\d]+ms)', s); 
    return m.group(1) if m else None

def jitter(s):
    m=re.search(r'jitter\s*([\d]+ms)', s); 
    return m.group(1) if m else None

def bool_bidir(s):
    return bool(re.search(r'\bbidir\b|both\s+directions', s))

def scenario_name(i, s):
    base = "impaired" if ("impair" in s or "loss" in s) else "baseline"
    p = ports(s)
    return f"{base}-{p[0][-1]}{p[1][-1]}-{i}" if p else f"{base}-{i}"

def build_yaml(defaults, scenarios):
    import yaml  # if PyYAML present, pretty; else manual
    return yaml.safe_dump(dict(defaults=defaults, scenarios=scenarios), sort_keys=False)

def build_yaml_min(defaults, scenarios):
    # Minimal YAML emitter if PyYAML isn't installed
    def emit_dict(d, indent=0):
        out=[]
        for k,v in d.items():
            if isinstance(v, dict):
                out.append(" " * indent + f"{k}:")
                out += emit_dict(v, indent+2)
            elif isinstance(v, list):
                out.append(" " * indent + f"{k}:")
                for item in v:
                    if isinstance(item, dict):
                        out.append(" "*(indent+2) + "-")
                        out += [ " "*(indent+4) + line for line in emit_dict(item, indent+4) ]
                    else:
                        out.append(" "*(indent+2) + f"- {item}")
            else:
                out.append(" " * indent + f"{k}: {v}")
        return out
    lines = emit_dict({"defaults": defaults, "scenarios": scenarios})
    return "\n".join(lines) + "\n"

def main():
    if len(sys.argv) < 2: 
        print(USAGE); sys.exit(1)
    text = " ".join(sys.argv[1:]).strip()
    clauses = [c.strip() for c in re.split(r';|\n', text) if c.strip()]

    defs = {
        "pps": 20000, "pktsize": 512, "count": 50000, "bidir": True,
        # controller comes from ../.env by run_dsl.py
        "impair": {"enabled": False, "loss": 1, "delay": "10ms", "jitter": "2ms"}
    }

    scs=[]
    for i, c in enumerate(clauses, start=1):
        p = ports(c) or ("eth1","eth2")
        scen = {
            "name": scenario_name(i, c),
            "ports": [p[0], p[1]],
            "pps": kpps_to_int(c) or defs["pps"],
            "pktsize": pktsize(c) or defs["pktsize"],
            "count": count_pkts(c) or defs["count"],
            "bidir": bool_bidir(c) or defs["bidir"],
        }
        if "impaired" in c or "impair" in c or loss(c) is not None:
            scen["impair"] = {
                "enabled": True,
                "loss": loss(c) or defs["impair"]["loss"],
                "delay": delay(c) or defs["impair"]["delay"],
                "jitter": jitter(c) or defs["impair"]["jitter"],
            }
        scs.append(scen)

    tmp_yaml = os.path.join(tempfile.gettempdir(), f"tests_{int(time.time())}.yaml")
    try:
        try:
            yaml_text = build_yaml(defs, scs)  # requires PyYAML
        except Exception:
            yaml_text = build_yaml_min(defs, scs)
        with open(tmp_yaml, "w", encoding="utf-8") as f:
            f.write(yaml_text)
        print(f"[NL] Wrote {tmp_yaml}")
        # run your DSL + report
        subprocess.run(["./run_dsl.py", tmp_yaml], check=True)
        subprocess.run(["./report.sh"], check=True)
    finally:
        pass 

if __name__ == "__main__":
    main()
