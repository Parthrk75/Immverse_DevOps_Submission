# Second target: the SAME platform module on a local kind cluster (no cloud account needed).
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    kind = { source = "tehcyx/kind", version = "~> 0.6" }
    helm = { source = "hashicorp/helm", version = "~> 2.15" }
  }
}

module "provider" {
  source = "../../provider/kind"
  name   = "local"
}

provider "helm" {
  kubernetes {
    host                   = module.provider.cluster_endpoint
    cluster_ca_certificate = base64decode(module.provider.cluster_ca_data)
    client_certificate     = module.provider.client_certificate
    client_key             = module.provider.client_key
  }
}

module "platform" {
  source                      = "../../platform"
  name                        = "local"
  tenant_label                = "local"
  ring                        = "dev"
  secret_store_kind           = module.provider.secret_store_kind
  region                      = "local"
  workload_identity           = module.provider.workload_identity
  ingress_service_annotations = module.provider.ingress_service_annotations
  storage_class               = module.provider.storage_class
  autoscaler                  = module.provider.autoscaler
  cluster_name                = module.provider.cluster_name
  cluster_gitops_dir          = "gitops/clusters/local-kind"
  enable_kyverno              = false
  enable_argocd               = false # local demo deploys the chart with helm (scripts/local.sh)
  ingress_local_mode          = true
}
