terraform {
  required_version = ">= 1.9.0"
  required_providers {
    kind = { source = "tehcyx/kind", version = "~> 0.6" }
    helm = { source = "hashicorp/helm", version = "~> 2.15" }
  }
}
