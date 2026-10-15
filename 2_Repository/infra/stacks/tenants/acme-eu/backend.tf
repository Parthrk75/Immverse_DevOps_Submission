terraform {
  backend "s3" {
    bucket       = "immverse-tfstate-eu"
    key          = "tenants/acme-eu/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }
}
