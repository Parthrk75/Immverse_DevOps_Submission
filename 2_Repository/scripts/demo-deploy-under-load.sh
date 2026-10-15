#!/usr/bin/env bash
# EVIDENCE 1: zero-downtime deploy under constant load. PASS = k6 reports 0 failed requests (threshold fails otherwise).
set -euo pipefail
cd "$(dirname "$0")/.."
export BASE=${BASE:-http://app.localtest.me:8080}
mkdir -p docs/evidence/out
k6 run -e SCALE=0.1 -e DURATION=4m loadtest/k6/steady.js --summary-export docs/evidence/out/deploy-under-load.json &
K6=$!
sleep 45
echo ">> shipping a GOOD v2 while load runs"
scripts/local.sh deploy v2
kubectl argo rollouts get rollout api -n app --watch --timeout 150s || true
wait $K6 && echo "PASS: no failed requests during rollout" || { echo "FAIL: errors during deploy"; exit 1; }
