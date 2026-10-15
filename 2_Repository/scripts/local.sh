#!/usr/bin/env bash
# One entry point for the LOCAL target (kind). Needs: docker, kind, kubectl, terraform, helm, k6.
#   scripts/local.sh up               registry + kind + platform (Terraform) + v1 deployed
#   scripts/local.sh deploy v2        build + push a GOOD release and roll it out (canary)
#   scripts/local.sh deploy v2-bad    build + push a BAD release (40% 5xx) and roll it out
#   scripts/local.sh status | down
# NOT RUN by the author (no Docker in the authoring sandbox): first run may need small fixes.
set -euo pipefail
cd "$(dirname "$0")/.."
REG=kind-registry; PORT=5001; CLUSTER=local
need(){ command -v "$1" >/dev/null || { echo "missing tool: $1"; exit 1; }; }

registry(){
  if [ "$(docker inspect -f '{{.State.Running}}' $REG 2>/dev/null || true)" != "true" ]; then
    docker run -d --restart=always -p 127.0.0.1:$PORT:5000 --network bridge --name $REG registry:2 >/dev/null
  fi
}
connect_registry(){ docker network connect kind $REG 2>/dev/null || true; }

build_push(){  # $1=tag  $2=extra docker build args ; prints the digest
  docker build -q -t localhost:$PORT/app:$1 $2 sample-app >/dev/null
  docker push -q localhost:$PORT/app:$1 >/dev/null
  docker inspect --format='{{index .RepoDigests 0}}' localhost:$PORT/app:$1 | cut -d@ -f2
}

secrets(){
  kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n app create secret generic app-secrets \
    --from-literal=pg_user=postgres --from-literal=pg_password=local-only-password \
    --from-literal=pg_host_direct=postgres-postgresql.data.svc.cluster.local \
    --from-literal=redis_host=redis-master.data.svc.cluster.local \
    --from-literal=redis_addr=redis-master.data.svc.cluster.local:6379 \
    --from-literal=redis_password="" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

deploy_digest(){ # $1=digest
  helm upgrade --install app gitops/charts/app -n app --create-namespace \
    -f gitops/clusters/local-kind/values.yaml --set image.digest="$1" --wait --timeout 5m
}

case "${1:-}" in
  up)
    for t in docker kind kubectl terraform helm; do need $t; done
    registry
    terraform -chdir=infra/stacks/local-kind init -input=false
    terraform -chdir=infra/stacks/local-kind apply -input=false -auto-approve -target=module.provider
    connect_registry
    terraform -chdir=infra/stacks/local-kind apply -input=false -auto-approve
    kubectl config use-context kind-$CLUSTER
    secrets
    D=$(build_push v1 "--build-arg RELEASE=v1")
    deploy_digest "$D"
    echo "UP. API: http://app.localtest.me:8080/healthz   (v1 digest $D)"
    ;;
  deploy)
    tag="${2:?usage: deploy v2|v2-bad}"
    case "$tag" in
      v2-bad) D=$(build_push v2-bad "--build-arg RELEASE=v2-bad --build-arg ERROR_RATE=0.4") ;;
      *)      D=$(build_push "$tag" "--build-arg RELEASE=$tag") ;;
    esac
    echo "deploying $tag = $D"
    helm upgrade --install app gitops/charts/app -n app -f gitops/clusters/local-kind/values.yaml --set image.digest="$D" --timeout 10m   # no --wait: the canary is watched by the demos
    ;;
  status)
    kubectl -n app get rollout,scaledobject,hpa,pods
    kubectl argo rollouts get rollout api -n app 2>/dev/null || true
    ;;
  down)
    terraform -chdir=infra/stacks/local-kind destroy -input=false -auto-approve || true
    kind delete cluster --name $CLUSTER || true
    docker rm -f $REG >/dev/null 2>&1 || true
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
