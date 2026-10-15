# provider/gcp  (STUB: not implemented, not run)

Reserved for the change request (second dedicated stack on another cloud). It must expose the
outputs listed in `../CONTRACT.md`. Planned mapping:

| contract | GCP resource |
|---|---|
| network | `terraform-google-modules/network` (VPC, subnets, Cloud NAT) |
| cluster | GKE Autopilot or Standard (`autoscaler = "cluster-autoscaler"`, or Karpenter-GCP when GA) |
| postgres | Cloud SQL for PostgreSQL (HA) + cross-region read replica for failover |
| redis | Memorystore for Redis (Standard tier, cross-region replica is not offered, see addendum) |
| secrets | Secret Manager + Workload Identity for External Secrets |
