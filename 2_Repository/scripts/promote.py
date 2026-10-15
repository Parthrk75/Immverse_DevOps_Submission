#!/usr/bin/env python3
"""Bump the image DIGEST of one ring (a promotion is a reviewed git change, never a rebuild).
  scripts/promote.py staging sha256:... [--pr]"""
import argparse, pathlib, re, subprocess, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fleet_rollout as fr

ap = argparse.ArgumentParser()
ap.add_argument("ring"); ap.add_argument("digest"); ap.add_argument("--pr", action="store_true")
a = ap.parse_args()
if not fr.DIGEST_RE.match(a.digest):
    sys.exit("refusing: use a sha256 digest, not a tag")
if not (fr.ROOT / "gitops/rings" / a.ring).is_dir():
    sys.exit(f"unknown ring {a.ring}")
f = fr.set_digest(a.ring, a.digest)
print(f"updated {f.relative_to(fr.ROOT)}")
if a.pr:
    br = f"promote/{a.ring}-{a.digest[7:19]}"
    for cmd in (["git", "checkout", "-b", br], ["git", "add", str(f)],
                ["git", "commit", "-m", f"promote {a.digest[:19]} to {a.ring}"],
                ["git", "push", "-u", "origin", br],
                ["gh", "pr", "create", "--fill", "--label", "promotion"]):
        subprocess.run(cmd, check=True)
