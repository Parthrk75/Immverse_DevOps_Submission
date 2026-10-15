terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.70" }
    helm   = { source = "hashicorp/helm", version = "~> 2.15" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "tenant" {
  source = "../../../modules/tenant"

  name      = "demo-eu"
  cloud     = "aws"
  region    = "eu-central-1"
  dr_region = "eu-west-1"
  size      = "s"
  residency = "eu"
  ring      = "ring0-internal"
}

provider "helm" {
  kubernetes {
    host                   = module.tenant.cluster_endpoint
    cluster_ca_certificate = base64decode(module.tenant.cluster_ca_data)
    exec {
      api_version = module.tenant.kube_exec.api_version
      command     = module.tenant.kube_exec.command
      args        = module.tenant.kube_exec.args
    }
  }
}
