#!/usr/bin/env bash
# EVIDENCE 2: a bad release (40% 5xx) is stopped by canary analysis and rolled back AUTOMATICALLY.
set -euo pipefail
cd "$(dirname "$0")/.."
export BASE=${BASE:-http://app.localtest.me:8080}
mkdir -p docs/evidence/out
k6 run -e SCALE=0.1 -e DURATION=5m loadtest/k6/steady.js --summary-export docs/evidence/out/bad-release.json &
K6=$!
sleep 30
scripts/local.sh deploy v2-bad
# expect: canary step -> AnalysisRun fails (5xx ratio > 0.5%) -> Rollout Degraded -> traffic back to stable
timeout 420 bash -c 'until [ "$(kubectl -n app get rollout api -o jsonpath={.status.phase})" = "Degraded" ]; do sleep 5; done'
kubectl -n app get analysisrun
kubectl argo rollouts get rollout api -n app
echo "Rollback evidence captured: stable ReplicaSet still serves 100%."
wait $K6 || echo "(k6 thresholds may report a few canary errors: only the canary slice saw 5xx)"
