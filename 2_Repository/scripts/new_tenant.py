#!/usr/bin/env python3
"""Stamp out a dedicated tenant from ONE command -> ONE reviewed PR.

  scripts/new_tenant.py --name acme-eu --residency eu --size m --ring ring1-small

Generates (all reviewed together in the PR):
  gitops/clusters/tenants/<name>/tenant.yaml      source of truth (schema checked in CI)
  gitops/clusters/tenants/<name>/values.yaml      Helm overrides (size, SLO, tenant label)
  gitops/clusters/tenants/<name>/application.yaml Argo CD Application (pull-based deploy)
  infra/stacks/tenants/<name>/{main.tf,backend.tf,terraform.tfvars}
"""
import argparse, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import validate_tenants as vt

ROOT = vt.ROOT
DEFAULTS = {
    ("eu", "aws"): ("eu-central-1", "eu-west-1"),
    ("us", "aws"): ("us-west-2", "us-east-1"),
    ("us", "gcp"): ("us-west1", "us-east4"),
    ("eu", "gcp"): ("europe-west3", "europe-west1"),
}
SIZE_VALUES = {  # replicas bounds by tenant size (autoscaling still applies)
    "s": dict(api_min=3, api_max=20, worker_min=1, worker_max=15),
    "m": dict(api_min=3, api_max=40, worker_min=2, worker_max=30),
    "l": dict(api_min=6, api_max=68, worker_min=4, worker_max=90),
}

TENANT = """name: {name}
tier: dedicated
residency: {residency}
cloud: {cloud}
region: {region}
dr_region: {dr_region}
size: {size}
ring: {ring}
slo: 99.95
owner: {owner}
"""
VALUES = """tenant: {name}
sloTarget: 99.95
sloErrorBudget: 0.0005
api:
  autoscaling: {{min: {api_min}, max: {api_max}}}
worker:
  autoscaling: {{min: {worker_min}, max: {worker_max}}}
"""
APP = """apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-{name}
  namespace: argocd
  labels: {{ring: {ring}}}
spec:
  project: default
  source:
    repoURL: https://github.com/immverse/devops-platform.git
    targetRevision: main
    path: gitops/charts/app
    helm:
      valueFiles:
        - ../../rings/{ring}/image.yaml
        - ../../clusters/tenants/{name}/values.yaml
  destination: {{server: https://kubernetes.default.svc, namespace: app}}
  syncPolicy:
    automated: {{prune: true, selfHeal: true}}
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
"""
MAIN_TF = """terraform {{
  required_version = ">= 1.9.0"
  required_providers {{
    aws    = {{ source = "hashicorp/aws", version = "~> 5.70" }}
    helm   = {{ source = "hashicorp/helm", version = "~> 2.15" }}
    random = {{ source = "hashicorp/random", version = "~> 3.6" }}
  }}
}}

provider "aws" {{
  region = "{region}"
}}

module "tenant" {{
  source = "../../../modules/tenant"

  name      = "{name}"
  cloud     = "{cloud}"
  region    = "{region}"
  dr_region = "{dr_region}"
  size      = "{size}"
  residency = "{residency}"
  ring      = "{ring}"
}}

provider "helm" {{
  kubernetes {{
    host                   = module.tenant.cluster_endpoint
    cluster_ca_certificate = base64decode(module.tenant.cluster_ca_data)
    exec {{
      api_version = module.tenant.kube_exec.api_version
      command     = module.tenant.kube_exec.command
      args        = module.tenant.kube_exec.args
    }}
  }}
}}
"""
BACKEND = """terraform {{
  backend "s3" {{
    bucket       = "immverse-tfstate-{residency}"
    key          = "tenants/{name}/terraform.tfstate"
    region       = "{state_region}"
    use_lockfile = true
    encrypt      = true
  }}
}}
"""
TFVARS = 'tenant_name = "{name}"\n'


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True)
    p.add_argument("--residency", required=True, choices=["eu", "us"])
    p.add_argument("--cloud", default="aws", choices=["aws", "gcp"])
    p.add_argument("--size", default="m", choices=sorted(vt.SIZES))
    p.add_argument("--ring", default="ring1-small", choices=sorted(vt.RINGS))
    p.add_argument("--owner", default="platform-team")
    p.add_argument("--root", default=str(ROOT), help="output root (used by tests)")
    a = p.parse_args()

    region, dr = DEFAULTS[(a.residency, a.cloud)]
    ctx = dict(vars(a), region=region, dr_region=dr, state_region=region, **SIZE_VALUES[a.size])
    doc = {"name": a.name, "residency": a.residency, "cloud": a.cloud, "region": region,
           "dr_region": dr, "size": a.size, "ring": a.ring, "slo": 99.95}
    errs = vt.validate_doc(doc, a.name)
    if errs:
        print("\n".join(errs)); return 1

    root = pathlib.Path(a.root)
    cdir = root / "gitops/clusters/tenants" / a.name
    sdir = root / "infra/stacks/tenants" / a.name
    if cdir.exists() or sdir.exists():
        print(f"tenant {a.name} already exists"); return 1
    cdir.mkdir(parents=True); sdir.mkdir(parents=True)
    (cdir / "tenant.yaml").write_text(TENANT.format(**ctx))
    (cdir / "values.yaml").write_text(VALUES.format(**ctx))
    (cdir / "application.yaml").write_text(APP.format(**ctx))
    (sdir / "main.tf").write_text(MAIN_TF.format(**ctx))
    (sdir / "backend.tf").write_text(BACKEND.format(**ctx))
    (sdir / "terraform.tfvars").write_text(TFVARS.format(**ctx))
    print(f"created tenant {a.name}: {cdir.relative_to(root)} and {sdir.relative_to(root)}")
    print("next: git checkout -b tenant/%s && git add -A && gh pr create" % a.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
