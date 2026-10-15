#!/usr/bin/env python3
"""Monthly cost model (USD). Unit prices are APPROXIMATE eu-central-1 list prices from
memory, NOT fetched live: verify in the AWS Pricing Calculator before committing.
Run: python3 scripts/cost.py"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import capacity

H = 730
P = dict(
    eks=0.10, m6i_xl=0.23, m6i_2xl=0.46, m6i_l=0.115, spot_factor=0.40,
    nat=0.052, nat_gb=0.052, alb=0.03, alb_lcu_month=25,
    acu=0.14, aurora_gb=0.11, aurora_io_per_m=0.22,
    redis_r6g_l=0.23, redis_t4g_m=0.07,
    egress_gb=0.09, s3_gb=0.0245, ebs_gb=0.095,
    waf_base=10, waf_per_m_req=0.60,
    cw_flat=150, r53_flat=25, kms_secrets=30,
)
PEAK_HOURS = 60  # assumption: 60 h/month at 15x


def shared(peak=False):
    r = capacity.compute()
    c = {}
    c["EKS control plane"] = P["eks"] * H
    # steady: 4 x m6i.xlarge on-demand (API + platform) + spot for workers
    steady_nodes = 4 * P["m6i_xl"] * H
    spot_workers = 1 * P["m6i_xl"] * P["spot_factor"] * H
    c["Compute (steady nodes)"] = steady_nodes + spot_workers
    if peak:
        extra_nodes = max(r["nodes_peak"] - 5, 0)
        api_od = extra_nodes * 0.4 * P["m6i_2xl"] * PEAK_HOURS
        wk_spot = extra_nodes * 0.6 * P["m6i_2xl"] * P["spot_factor"] * PEAK_HOURS
        c["Compute (peak burst, %d h)" % PEAK_HOURS] = api_od + wk_spot
    # Aurora Serverless v2: writer+reader (reader tracks writer, tier 0)
    acu_avg = r["db_acu_base"] * 2 * 1.5
    c["Aurora PG Serverless v2 (steady)"] = acu_avg * P["acu"] * H
    if peak:
        c["Aurora burst ACU (%d h)" % PEAK_HOURS] = (r["db_acu_peak"] * 2 - acu_avg) * P["acu"] * PEAK_HOURS
    c["Aurora storage+IO"] = 400 * P["aurora_gb"] + 250 * P["aurora_io_per_m"]
    c["ElastiCache Redis (2x r6g.large, Multi-AZ)"] = 2 * P["redis_r6g_l"] * H
    c["NAT (3 AZ) hourly"] = 3 * P["nat"] * H
    nat_gb = 3000 + (1500 if peak else 0)
    c["NAT data processing"] = nat_gb * P["nat_gb"]
    c["ALB + LCU"] = P["alb"] * H + P["alb_lcu_month"] * (2 if peak else 1)
    req_m = 150 * 3600 * 24 * 30 / 1e6 + (2100 * 3600 * PEAK_HOURS / 1e6 if peak else 0)
    c["WAF (requests)"] = P["waf_base"] + req_m * P["waf_per_m_req"]
    egress = 5000 + (3000 if peak else 0)
    c["Data transfer out"] = egress * P["egress_gb"]
    c["Observability (CloudWatch+EBS+S3 for Prom/Loki)"] = P["cw_flat"] + 500 * P["ebs_gb"] + 1500 * P["s3_gb"]
    c["Route53, KMS, Secrets Manager, ECR"] = P["r53_flat"] + P["kms_secrets"] + 20
    c["Backups (snapshots, cross-region EU copy)"] = 120
    return c


def tenant(size="m"):
    nodes = {"s": 3 * P["m6i_l"], "m": 3 * P["m6i_xl"], "l": 3 * P["m6i_2xl"]}[size]
    acu = {"s": 1, "m": 2, "l": 4}[size]  # min ACU per instance
    c = {
        "EKS": P["eks"] * H,
        "Compute": nodes * H,
        "Aurora SV2 (writer+reader, avg ACU)": acu * 2 * 1.4 * P["acu"] * H,
        "Redis (2x t4g.medium)": 2 * P["redis_t4g_m"] * H,
        "NAT x3": 3 * P["nat"] * H + 400 * P["nat_gb"],
        "ALB": P["alb"] * H + 10,
        "Obs (remote-write to regional), logs, backups, KMS": 120,
    }
    return c


def show(title, c):
    print(f"\n## {title}")
    for k, v in c.items():
        print(f"| {k:50s} | {v:10,.0f} |")
    tot = sum(c.values())
    print(f"| {'TOTAL':50s} | {tot:10,.0f} |")
    return tot


if __name__ == "__main__":
    s, p = show("Shared stack - steady", shared()), show("Shared stack - month with 60 h peak", shared(True))
    t = {z: show(f"Dedicated tenant size {z}", tenant(z)) for z in "sml"}
    print("\n## Budget check")
    print(f"Steady budget 9,000: shared {s:,.0f} -> remaining {9000 - s:,.0f} -> room for {int((9000 - s) // t['m'])} size-m dedicated tenants")
    print(f"Peak budget 16,000: shared peak month {p:,.0f}; with 4 size-m tenants {p + 4 * t['m']:,.0f}")
