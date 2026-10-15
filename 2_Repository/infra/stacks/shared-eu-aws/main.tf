terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.70" }
    helm   = { source = "hashicorp/helm", version = "~> 2.15" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "s3" {
    bucket       = "immverse-tfstate-eu"
    key          = "shared-eu/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "eu-central-1"
  default_tags { tags = { stack = "shared-eu", managed-by = "terraform" } }
}

module "provider" {
  source              = "../../provider/aws"
  name                = "shared-eu"
  region              = "eu-central-1"
  dr_region           = "eu-west-1"
  residency           = "eu"
  size                = "l"
  db_max_acu_override = 48
  tags                = { tier = "shared", env = "prod" }
}

provider "helm" {
  kubernetes {
    host                   = module.provider.cluster_endpoint
    cluster_ca_certificate = base64decode(module.provider.cluster_ca_data)
    exec {
      api_version = module.provider.kube_exec.api_version
      command     = module.provider.kube_exec.command
      args        = module.provider.kube_exec.args
    }
  }
}

module "platform" {
  source                      = "../../platform"
  name                        = "shared-eu"
  tenant_label                = "shared"
  ring                        = "shared-prod"
  secret_store_kind           = module.provider.secret_store_kind
  region                      = "eu-central-1"
  workload_identity           = module.provider.workload_identity
  ingress_service_annotations = module.provider.ingress_service_annotations
  storage_class               = module.provider.storage_class
  autoscaler                  = module.provider.autoscaler
  cluster_name                = module.provider.cluster_name
  cluster_gitops_dir          = "gitops/clusters/shared-eu"
}
