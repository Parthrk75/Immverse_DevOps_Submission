variable "name" { type = string }
variable "tenant_label" {
  type        = string
  description = "Value of the 'tenant' external label on all metrics (per-tenant visibility)."
}
variable "ring" {
  type        = string
  description = "Rollout ring label attached to metrics (used by fleet gates)."
}
variable "secret_store_kind" { type = string }
variable "region" { type = string }
variable "workload_identity" {
  type    = map(string)
  default = {}
}
variable "ingress_service_annotations" {
  type    = map(string)
  default = {}
}
variable "storage_class" { type = string }
variable "autoscaler" { type = string }
variable "cluster_name" { type = string }
variable "remote_write_url" {
  type        = string
  default     = ""
  description = "Regional (same-residency) Prometheus/Mimir endpoint. Empty = keep metrics local only."
}
variable "gitops_repo" {
  type    = string
  default = "https://github.com/immverse/devops-platform.git"
}
variable "gitops_revision" {
  type    = string
  default = "main"
}
variable "cluster_gitops_dir" {
  type        = string
  description = "Path in the repo holding this cluster's Argo Application, e.g. gitops/clusters/shared-eu"
}
variable "enable_argocd" {
  type    = bool
  default = true
}
variable "ingress_local_mode" {
  type        = bool
  default     = false
  description = "kind: NodePort + hostPort on the control-plane node instead of a cloud load balancer."
}
variable "enable_kyverno" {
  type    = bool
  default = true
}
