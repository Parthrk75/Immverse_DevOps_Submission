#!/usr/bin/env bash
# Push N jobs onto the Redis list (queue-depth autoscaling + "no job lost" test). Usage: enqueue-jobs.sh 2000
set -euo pipefail
N="${1:-2000}"
kubectl -n data exec deploy/redis-master -- sh -c "for i in \$(seq 1 $N); do echo RPUSH jobs job-\$i; done | redis-cli --pipe" >/dev/null 2>&1 \
 || kubectl -n data exec redis-master-0 -- sh -c "for i in \$(seq 1 $N); do echo RPUSH jobs job-\$i; done | redis-cli --pipe"
echo "enqueued $N; queue length: $(kubectl -n data exec redis-master-0 -- redis-cli LLEN jobs)"
