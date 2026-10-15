#!/usr/bin/env bash
# EVIDENCE 3: scaled-down 15x test + queue-depth scaling + no job lost on scale-in.
set -euo pipefail
cd "$(dirname "$0")/.."
export BASE=${BASE:-http://app.localtest.me:8080}
mkdir -p docs/evidence/out
kubectl -n app get hpa -w > docs/evidence/out/hpa-watch.log 2>&1 &
W=$!
./loadtest/enqueue-jobs.sh 3000
k6 run -e SCALE=0.05 loadtest/k6/peak.js --summary-export docs/evidence/out/peak.json || true
kill $W || true
echo "queue left: $(kubectl -n data exec redis-master-0 -- redis-cli LLEN jobs)"
echo "jobs completed: $(kubectl -n app logs -l app=worker --tail=-1 | grep -c 'job done' || true)"
echo "clean drains:   $(kubectl -n app logs -l app=worker --tail=-1 | grep -c 'drained cleanly' || true)"
