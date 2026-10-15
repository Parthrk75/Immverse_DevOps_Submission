#!/usr/bin/env python3
"""Validate tenant definitions and enforce data residency (CI gate).

Rules
  * one directory per tenant: gitops/clusters/tenants/<name>/tenant.yaml
  * residency eu  -> cloud region AND dr_region must both be EU regions
  * residency us  -> both must be US regions
  * the Terraform stack for the tenant may not reference any region outside its residency
Exit code 1 on any violation, so the pipeline fails before anything is applied.
"""
import pathlib, re, sys
import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
TENANT_DIR = ROOT / "gitops" / "clusters" / "tenants"
STACK_DIR = ROOT / "infra" / "stacks" / "tenants"

REGIONS = {
    "eu": {"aws": {"eu-central-1", "eu-west-1"},
           "gcp": {"europe-west3", "europe-west1"},
           "azure": {"germanynorth", "germanywestcentral", "northeurope", "westeurope"}},
    "us": {"aws": {"us-west-2", "us-east-1", "us-east-2"},
           "gcp": {"us-west1", "us-east4", "us-east1"},
           "azure": {"westus3", "eastus2", "westus2", "eastus"}},
}
RINGS = {"ring0-internal", "ring1-small", "ring2-large"}
SIZES = {"s", "m", "l"}
NAME_RE = re.compile(r"^[a-z][a-z0-9-]{2,30}$")
REGION_TOKEN = re.compile(r'"((?:us|eu|ap|sa|ca|me|af|il|mx)-[a-z]+-\d)"')


def all_regions(residency_other):
    return {r for c in REGIONS[residency_other].values() for r in c}


def validate_doc(doc, folder_name):
    errs = []
    for key in ("name", "residency", "cloud", "region", "dr_region", "size", "ring", "slo"):
        if key not in doc:
            errs.append(f"missing key '{key}'")
    if errs:
        return errs
    if doc["name"] != folder_name:
        errs.append(f"name '{doc['name']}' != folder '{folder_name}'")
    if not NAME_RE.match(str(doc["name"])):
        errs.append("name must match ^[a-z][a-z0-9-]{2,30}$")
    res, cloud = doc["residency"], doc["cloud"]
    if res not in REGIONS:
        return errs + [f"residency '{res}' not in {sorted(REGIONS)}"]
    if cloud not in REGIONS[res]:
        return errs + [f"cloud '{cloud}' unsupported"]
    allowed = REGIONS[res][cloud]
    for k in ("region", "dr_region"):
        if doc[k] not in allowed:
            errs.append(f"{k} '{doc[k]}' violates residency '{res}' (allowed: {sorted(allowed)})")
    if doc["region"] == doc["dr_region"]:
        errs.append("dr_region must differ from region")
    if doc["ring"] not in RINGS:
        errs.append(f"ring must be one of {sorted(RINGS)}")
    if doc["size"] not in SIZES:
        errs.append(f"size must be one of {sorted(SIZES)}")
    if float(doc["slo"]) < 99.9 or float(doc["slo"]) > 99.99:
        errs.append("slo must be between 99.9 and 99.99")
    return errs


def scan_stack(name, residency):
    """Fail if a tenant's Terraform references a region outside its residency."""
    errs = []
    d = STACK_DIR / name
    if not d.exists():
        return [f"no Terraform stack for tenant {name}"]
    forbidden = all_regions("us" if residency == "eu" else "eu")
    for f in list(d.glob("*.tf")) + list(d.glob("*.tfvars")):
        for tok in REGION_TOKEN.findall(f.read_text()):
            if tok in forbidden:
                errs.append(f"{f.name} in stacks/tenants/{name} references {tok} outside residency '{residency}'")
    return errs


def main():
    failures, names = 0, set()
    for tf in sorted(TENANT_DIR.glob("*/tenant.yaml")):
        doc = yaml.safe_load(tf.read_text()) or {}
        name = tf.parent.name
        errs = validate_doc(doc, name)
        if name in names:
            errs.append("duplicate tenant name")
        names.add(name)
        if not errs:
            errs += scan_stack(name, doc["residency"])
        status = "OK  " if not errs else "FAIL"
        print(f"[{status}] {name}")
        for e in errs:
            print(f"        - {e}")
        failures += bool(errs)
    print(f"{len(names)} tenant(s) checked, {failures} failing")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
