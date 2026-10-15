# Cloud-agnostic, automated, zero-downtime deployment platform

Answer to the *Senior DevOps Assignment* (ImmverseAI). Design and code for a platform that provisions infrastructure on any cloud, deploys an application through multi-stage, metric-gated pipelines with zero downtime, scales 15x in under 5 minutes, and supports one shared stack plus dedicated per-tenant stacks with EU data residency.

> **Read this first: what is real and what is not.** The environment this was written in had no Terraform, Kubernetes, Docker or network. The Python tooling, tests, models and simulations **were run** (outputs in `docs/evidence/out/`). The Terraform, Helm chart, pipelines and manifests were **written and desk-reviewed but never executed**, and the four recordings the brief asks for were **not produced**. Details in [`docs/RUN-STATUS.md`](docs/RUN-STATUS.md). Expect small fixes on first `terraform plan` / `helm lint`; start with `make lint`.

> **To run it, follow [`docs/HOW-TO-RUN.md`](docs/HOW-TO-RUN.md)** (Docker Compose, local kind, AWS, Jenkins; one document).

## Deliverables map

| Brief deliverable | Where |
|---|---|
| Git repo with README, IaC, pipelines, scripts | this repository |
| Architecture document (max 5 pages): diagram, 7 decisions with rejected alternatives, top 5 risks | [`docs/ARCHITECTURE.pdf`](docs/ARCHITECTURE.pdf) (4 pages) / `.docx` / `.md` |
| Evidence (deploy under load, rollback, 15x, restore) | [`docs/evidence/`](docs/evidence/README.md): outputs that ran, plus scripts and pass criteria for the ones that did not |
| Change request addendum (one page) | To be sent separately after the change request is released (24 h) |

## Layout

```
infra/
  bootstrap/aws/      empty account -> remote state (S3 native lock, KMS) + CI OIDC role
  provider/           ONLY cloud-specific code. CONTRACT.md = inputs/outputs every provider obeys
    aws/  kind/  gcp/(stub)
  platform/           ingress, Argo CD + Rollouts, KEDA, Prometheus/Grafana/Loki, ESO, Kyverno (portable)
  modules/tenant/     provider + platform with tenant presets
  stacks/             shared-eu-aws, local-kind, tenants/<name> (generated)
  policies/           EU-residency SCP + conftest rego
gitops/
  charts/app/         Helm: API canary, worker, KEDA, PDBs, migration hook, PgBouncer, alerts
  rings/<ring>/       image.yaml = the DIGEST each ring runs (promotion = PR on this file)
  clusters/           per-cluster Argo Application + values; tenants/<name>/tenant.yaml
  platform/           per-cloud cluster config charts (Karpenter pools, secret store, signature policy)
  rollout-plan.yaml   wave order + metric gates
jenkins/              Jenkinsfile (build/scan/sign), .promote (gated), .infra (plan + drift)
scripts/              new_tenant, validate_tenants, migration_lint, fleet_rollout, promote, gate_check,
                      capacity, cost, restore-test, kind-up, demo-*
loadtest/             k6 (peak 15x, steady) + job enqueuer
ops/                  dashboard, backup CronJob
sample-app/           stand-in for the black-box app (local demo + bad-release injection only)
tests/                16 unit tests
docs/                 architecture, capacity, cost, SLOs, not-portable, roadmap, runbooks, evidence
```

## Quick start

```bash
make test              # runs anywhere: python3 + pyyaml
make validate          # tenant schema + EU residency gate
make capacity cost     # the models behind the numbers
make new-tenant NAME=acme-eu RES=eu SIZE=m RING=ring1-small   # one command -> one PR

# needs docker, kind, kubectl, terraform, helm, k6, kubectl-argo-rollouts:
make lint              # terraform validate, helm lint/template + kubeconform
make local-up          # kind target: same platform module as AWS (scripts/local.sh)
make compose-up        # simplest: docker compose, no Kubernetes
make jenkins-up        # local Jenkins + registry
make demo-deploy       # evidence 1: zero-downtime deploy under load
make demo-rollback     # evidence 2: bad release rolled back automatically
make demo-scale        # evidence 3: scaled-down 15x + queue-depth scaling
make restore-test      # evidence 4

# AWS (costs money; read docs/COST.md first):
terraform -chdir=infra/bootstrap/aws apply -var residency=eu -var region=eu-central-1
scripts/tf-apply.sh infra/stacks/shared-eu-aws
```

## Design in five lines

1. **Build once, promote the digest.** Jenkins builds, scans, signs; every environment runs the same `sha256`; Kyverno rejects anything unsigned or tag-referenced.
2. **GitOps pull** (Argo CD per cluster). Promotion is a reviewed PR; the fleet pipeline walks dev, staging, shared, ring0, ring1, ring2, other region and **halts on the first red metric gate**.
3. **API canary** (5/25/50/100) with Prometheus analysis and automatic abort; **worker rolling with draining** (grace 90 s > 60 s jobs).
4. **Safe migrations:** lint gate, expand/contract policy, one PreSync Job under an advisory lock, PITR as last resort.
5. **15x in under 5 min:** KEDA (RPS and Redis queue depth) + Karpenter + pause-pod headroom + Aurora Serverless v2 + PgBouncer, with the maths in [`docs/CAPACITY.md`](docs/CAPACITY.md).

## Assumptions about the black-box app (change in one place: `gitops/charts/app/values.yaml`)

A1 a migrate-only mode exists; A2 worker drains on SIGTERM and jobs are idempotent; A3 metric names `http_requests_total{status}` / `http_request_duration_seconds_bucket`; A4 no session state or server-side prepared statements (PgBouncer transaction mode). These are the top risks in the architecture doc.

## Known shortcuts (not hidden)

Bootstrap CI role is Administrator; the first-pass cost prices are unverified; Terraform needs a two-phase apply (cluster, then Helm provider); `redis_exporter` and Pushgateway are referenced but not yet installed by the platform module; the tenant template is AWS-only (see addendum); no cross-region DR has been exercised.
