#!/usr/bin/env python3
"""Capacity maths. Every number below is an ASSUMPTION to be replaced by measurements
from the k6 load test (loadtest/k6/peak.js). Run: python3 scripts/capacity.py"""
import math

A = dict(
    rps_base=150, rps_peak=2250,
    rps_per_api_pod=40,        # at ~70% CPU of 1 vCPU (assumed, measure!)
    api_vcpu=1.0, api_mem_gib=1.0,
    api_headroom=0.20,         # absorbs a pod/AZ blip while HPA reacts
    api_min_replicas=6,        # 2 per AZ x 3 AZ
    api_db_pool=10,
    jobs_peak_per_hr=20000,
    avg_job_s=20, max_job_s=60,  # avg is an assumption; 60 s is given
    worker_slots_per_pod=4, worker_vcpu=0.5, worker_mem_gib=0.5,
    worker_headroom=0.30, worker_db_pool=2,
    queue_target_per_pod=8,    # KEDA listLength: 2 queued jobs per slot
    node_vcpu_alloc=7.4,       # m6i.2xlarge allocatable
    platform_vcpu=6,           # ingress, argo, keda, prometheus, loki, grafana ...
    pgbouncer_server_conns=150,
    db_ms_cpu_per_req=3.0, db_vcpu_per_acu=0.25,
)


def compute(a=A):
    r = {}
    r["api_pods_base"] = max(math.ceil(a["rps_base"] / a["rps_per_api_pod"] * (1 + a["api_headroom"])), a["api_min_replicas"])
    r["api_pods_peak"] = math.ceil(a["rps_peak"] / a["rps_per_api_pod"] * (1 + a["api_headroom"]))
    jobs_s = a["jobs_peak_per_hr"] / 3600
    r["jobs_per_s_peak"] = jobs_s
    r["jobs_per_s_base"] = jobs_s / (a["rps_peak"] / a["rps_base"])
    r["conc_avg_peak"] = jobs_s * a["avg_job_s"]
    r["conc_worst_peak"] = jobs_s * a["max_job_s"]
    r["worker_pods_peak_avg"] = math.ceil(r["conc_avg_peak"] / a["worker_slots_per_pod"] * (1 + a["worker_headroom"]))
    r["worker_pods_peak_worst"] = math.ceil(r["conc_worst_peak"] / a["worker_slots_per_pod"])
    r["worker_pods_base"] = max(2, math.ceil(r["jobs_per_s_base"] * a["avg_job_s"] / a["worker_slots_per_pod"] * (1 + a["worker_headroom"])))
    r["worker_max_replicas"] = r["worker_pods_peak_worst"] + 6
    # vCPU & nodes
    peak_vcpu = (r["api_pods_peak"] * a["api_vcpu"] + r["worker_pods_peak_worst"] * a["worker_vcpu"] + a["platform_vcpu"])
    base_vcpu = (r["api_pods_base"] * a["api_vcpu"] + r["worker_pods_base"] * a["worker_vcpu"] + a["platform_vcpu"])
    r["vcpu_peak"], r["vcpu_base"] = peak_vcpu, base_vcpu
    r["nodes_peak"] = math.ceil(peak_vcpu / a["node_vcpu_alloc"])
    r["nodes_base"] = math.ceil(base_vcpu / 3.4)  # m6i.xlarge: ~3.4 vCPU allocatable
    # DB connections
    r["client_conns_peak"] = r["api_pods_peak"] * a["api_db_pool"] + r["worker_pods_peak_worst"] * a["worker_db_pool"]
    r["client_conns_no_pooler_api_only"] = r["api_pods_peak"] * a["api_db_pool"]
    r["server_conns_with_pgbouncer"] = a["pgbouncer_server_conns"]
    # DB compute
    db_cores_peak = a["rps_peak"] * a["db_ms_cpu_per_req"] / 1000 + jobs_s * 0.05
    r["db_vcpu_peak"] = db_cores_peak
    r["db_acu_peak"] = math.ceil(db_cores_peak / a["db_vcpu_per_acu"])
    r["db_acu_base"] = max(4, math.ceil(a["rps_base"] * a["db_ms_cpu_per_req"] / 1000 / a["db_vcpu_per_acu"]))
    return r


def scale_timeline():
    """Design timeline for a step from 1x to 15x (target < 300 s). Not measured."""
    return [
        (0,   "Traffic ramps; Prometheus scrape (15 s) sees RPS climb"),
        (30,  "KEDA (poll 15 s) -> HPA desired replicas jump to peak; scaleUp policy: +100% / 15 s, max 30 pods"),
        (35,  "Overprovisioning pause pods (low PriorityClass) are evicted -> ~20 API pods schedule on warm nodes"),
        (45,  "Karpenter sees Pending pods, launches nodes (batched, spot+on-demand, 2 instance families)"),
        (150, "New nodes Ready (~90-110 s typical), image already cached via pre-pulled AMI / ECR pull-through"),
        (180, "API pods Running + readiness (/readyz) pass; ingress adds endpoints"),
        (210, "Worker pods scale via KEDA Redis listLength (queue depth) -> backlog drains"),
        (240, "Steady at ~peak replicas; target met with ~60 s margin"),
    ]


if __name__ == "__main__":
    r = compute()
    print("# Capacity model (assumptions in scripts/capacity.py)\n")
    for k, v in r.items():
        print(f"{k:40s} {v:,.1f}" if isinstance(v, float) else f"{k:40s} {v:,}")
    print("\n# Scale-up timeline (design, not measured)")
    for t, e in scale_timeline():
        print(f"T+{t:>3}s  {e}")
