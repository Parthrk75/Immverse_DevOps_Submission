# Provider contract

Every provider module (`aws/`, `kind/`, future `gcp/`, `azure/`) takes the same inputs and
returns the same outputs. The platform and app layers consume ONLY these outputs, so they
never import a cloud-specific resource.

## Inputs
| name | type | meaning |
|---|---|---|
| `name` | string | stack name (`shared-eu`, tenant name, `local`) |
| `region` / `dr_region` | string | primary / DR region (same residency domain) |
| `residency` | `eu` \| `us` \| `local` | enforced by policy, not just by convention |
| `size` | `s`\|`m`\|`l` | node, DB and cache sizing preset |
| `tags` | map | cost allocation (`tenant`, `env`, `owner`) |

## Outputs
| name | meaning |
|---|---|
| `cluster_name`, `cluster_endpoint`, `cluster_ca_data` | Kubernetes API access |
| `kube_exec` | exec-plugin args for token auth (no static kubeconfig) |
| `postgres_host`, `postgres_port`, `postgres_secret_name` | Postgres endpoint + secret **name** in the secrets manager |
| `redis_host`, `redis_port`, `redis_secret_name` | Redis endpoint + secret name |
| `secret_store_kind` | `aws-secretsmanager` \| `gcp-secretmanager` \| `kubernetes` (drives the ESO ClusterSecretStore) |
| `storage_class` | default StorageClass for stateful platform parts |
| `ingress_service_annotations` | LB annotations for the ingress Service (the non-portable bit) |
| `workload_identity` | map of IAM role ARNs / GSA emails per component (ESO, Karpenter, Loki) |
| `autoscaler` | `karpenter` \| `cluster-autoscaler` \| `none` |

Anything cloud-specific lives behind these names. See `docs/NOT-PORTABLE.md`.
