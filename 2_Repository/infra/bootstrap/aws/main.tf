# Run ONCE per account/residency domain with admin credentials (local state), then migrate to remote:
#   terraform init && terraform apply -var residency=eu -var region=eu-central-1
# Creates: encrypted/versioned state bucket (native S3 locking), KMS key, GitHub-OIDC CI role.
terraform {
  required_version = ">= 1.9.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.70" } }
}
variable "residency" { type = string }
variable "region" { type = string }
variable "github_repo" {
  type    = string
  default = "immverse/devops-platform"
}
provider "aws" { region = var.region }

resource "aws_kms_key" "state" {
  description         = "terraform state ${var.residency}"
  enable_key_rotation = true
}
resource "aws_s3_bucket" "state" {
  bucket = "immverse-tfstate-${var.residency}"
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
resource "aws_iam_role" "ci" {
  name = "immverse-ci-${var.residency}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*" }
      }
    }]
  })
}
# Scope down before production: AdministratorAccess is for the bootstrap demo only (documented risk).
resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "ci_role_arn" { value = aws_iam_role.ci.arn }
