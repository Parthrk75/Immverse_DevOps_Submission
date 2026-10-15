#!/usr/bin/env python3
"""Metric gate between waves: query Prometheus for the previous wave; exit 1 if outside SLO."""
import argparse, json, sys, urllib.parse, urllib.request
import yaml, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser(); ap.add_argument("--wave", required=True); ap.add_argument("--target", required=True)
ap.add_argument("--prom-url", required=True); a = ap.parse_args()
waves = yaml.safe_load((ROOT / "gitops/rollout-plan.yaml").read_text())["waves"]
names = [w["name"] for w in waves]
tgt = a.target if a.target != "fleet" else "ring0-internal"
i = names.index(tgt)
if i == 0:
    print("first wave: no gate"); sys.exit(0)
prev = waves[i - 1]
for g in prev["gates"]:
    q = g["query"].replace("$WAVE", prev["name"])
    url = f"{a.prom_url}/api/v1/query?" + urllib.parse.urlencode({"query": q})
    res = json.load(urllib.request.urlopen(url))["data"]["result"]
    if not res:
        print(f"gate {g['name']}: NO DATA for wave {prev['name']} -> fail closed"); sys.exit(1)
    v = float(res[0]["value"][1]); ok = v <= g["max"]
    print(f"gate {g['name']}: {v:.4f} <= {g['max']} {'ok' if ok else 'BREACH'}")
    if not ok: sys.exit(1)
