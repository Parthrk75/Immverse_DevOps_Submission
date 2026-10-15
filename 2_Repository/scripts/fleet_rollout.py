#!/usr/bin/env python3
"""Fleet rollout orchestrator: promote ONE image digest wave by wave, halting on failure.

Order (gitops/rollout-plan.yaml): dev -> staging -> shared-prod -> ring0-internal ->
ring1-small -> ring2-large -> region-us.  A wave is 'promoted' by committing the digest into
gitops/rings/<wave>/image.yaml (Argo CD pulls it). A wave is 'green' only when
  1) every Argo CD Application of that wave is Synced+Healthy, AND
  2) the metric gates (error ratio, p95) are inside SLO for the soak period.
Any red wave stops the rollout; later waves are never touched. Rollback = git revert.

  --dry-run   simulate (no git, no cluster); --fail-at <wave> injects a failure (demo/tests)
"""
import argparse, pathlib, re, subprocess, sys, time
import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def load_plan():
    return yaml.safe_load((ROOT / "gitops/rollout-plan.yaml").read_text())["waves"]


def set_digest(wave, digest, root=ROOT):
    f = root / "gitops/rings" / wave / "image.yaml"
    txt = f.read_text()
    new, n = re.subn(r'(digest:\s*)"?[^"\n#]*"?', rf'\1"{digest}"', txt, count=1)
    if n != 1:
        raise RuntimeError(f"cannot set digest in {f}")
    f.write_text(new)
    return f


def argo_healthy(wave):  # real mode: query Argo CD
    out = subprocess.run(["argocd", "app", "list", "-l", f"ring={wave}", "-o", "json"],
                         capture_output=True, text=True, check=True).stdout
    import json
    apps = json.loads(out)
    return bool(apps) and all(a["status"]["sync"]["status"] == "Synced" and a["status"]["health"]["status"] == "Healthy" for a in apps)


def prom_gate(wave, gates, prom_url):  # real mode: query Prometheus
    import json, urllib.parse, urllib.request
    for g in gates:
        q = g["query"].replace("$WAVE", wave)
        u = f"{prom_url}/api/v1/query?" + urllib.parse.urlencode({"query": q})
        val = float(json.load(urllib.request.urlopen(u))["data"]["result"][0]["value"][1])
        ok = val <= g["max"]
        print(f"      gate {g['name']}: {val:.4f} (max {g['max']}) {'ok' if ok else 'BREACH'}")
        if not ok:
            return False
    return True


def run(digest, dry, fail_at, prom_url, start_at=None):
    if not DIGEST_RE.match(digest):
        print("refusing: image must be referenced by sha256 digest, not a tag"); return 2
    waves, started = load_plan(), start_at is None
    for w in waves:
        if not started:
            started = w["name"] == start_at
            if not started:
                continue
        print(f"==> wave {w['name']}  (soak {w.get('soak_s', 0)} s)")
        if dry:
            print(f"    [dry-run] would write digest to gitops/rings/{w['name']}/image.yaml and open PR")
            ok = w["name"] != fail_at
            if not ok:
                print("    [dry-run] injected failure: 5xx ratio 4.2% > 0.5%")
        else:
            f = set_digest(w["name"], digest)
            subprocess.run(["git", "add", str(f)], check=True)
            subprocess.run(["git", "commit", "-m", f"promote {digest[:19]} to {w['name']}"], check=True)
            subprocess.run(["git", "push"], check=True)
            time.sleep(w.get("soak_s", 0))
            ok = argo_healthy(w["name"]) and prom_gate(w["name"], w["gates"], prom_url)
        print(f"    result: {'GREEN' if ok else 'RED'}")
        if not ok:
            print(f"HALT: wave '{w['name']}' failed. Waves after it were NOT promoted. Revert with: git revert <promote commit>")
            return 1
    print("fleet rollout complete")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("digest")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--fail-at")
    ap.add_argument("--start-at")
    ap.add_argument("--prom-url", default="http://prometheus.monitoring:9090")
    a = ap.parse_args()
    sys.exit(run(a.digest, a.dry_run, a.fail_at, a.prom_url, a.start_at))
