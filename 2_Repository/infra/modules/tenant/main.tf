# One tenant = one provider stack + one platform stack, from the same template as the shared stack.
# Only the AWS provider is wired here; adding gcp = a new `module "provider_gcp"` + count switch.
terraform {
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.70" }
    helm = { source = "hashicorp/helm", version = "~> 2.15" }
  }
}

check "cloud_supported" {
  assert {
    condition     = var.cloud == "aws"
    error_message = "Only cloud=aws is implemented; see infra/provider/gcp/README.md."
  }
}

module "provider" {
  source    = "../../provider/aws"
  name      = var.name
  region    = var.region
  dr_region = var.dr_region
  residency = var.residency
  size      = var.size
  tags      = { tenant = var.name, tier = "dedicated" }
}

module "platform" {
  source                      = "../../platform"
  name                        = var.name
  tenant_label                = var.name
  ring                        = var.ring
  secret_store_kind           = module.provider.secret_store_kind
  region                      = var.region
  workload_identity           = module.provider.workload_identity
  ingress_service_annotations = module.provider.ingress_service_annotations
  storage_class               = module.provider.storage_class
  autoscaler                  = module.provider.autoscaler
  cluster_name                = module.provider.cluster_name
  remote_write_url            = var.remote_write_url
  cluster_gitops_dir          = "gitops/clusters/tenants/${var.name}"
}

output "cluster_name" { value = module.provider.cluster_name }
output "postgres_secret_name" { value = module.provider.postgres_secret_name }
output "cluster_endpoint" { value = module.provider.cluster_endpoint }
output "cluster_ca_data" { value = module.provider.cluster_ca_data }
output "kube_exec" { value = module.provider.kube_exec }
