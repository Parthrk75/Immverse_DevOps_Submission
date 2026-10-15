# AWS provider layer: network, Kubernetes (EKS), Postgres (Aurora Serverless v2), Redis, secrets.
# Residency guard: refuse to plan if the region is outside the declared residency domain.
locals {
  eu_regions = ["eu-central-1", "eu-west-1"]
  us_regions = ["us-west-2", "us-east-1", "us-east-2"]
  allowed    = var.residency == "eu" ? local.eu_regions : local.us_regions

  preset = {
    s = { node_type = "m6i.large", min_nodes = 3, max_acu = 8, min_acu = 1, redis = "cache.t4g.medium" }
    m = { node_type = "m6i.xlarge", min_nodes = 3, max_acu = 16, min_acu = 2, redis = "cache.t4g.medium" }
    l = { node_type = "m6i.2xlarge", min_nodes = 4, max_acu = 48, min_acu = 4, redis = "cache.r6g.large" }
  }[var.size]
  max_acu = coalesce(var.db_max_acu_override, local.preset.max_acu)
  tags    = merge(var.tags, { stack = var.name, residency = var.residency, managed-by = "terraform" })
}

check "residency" {
  assert {
    condition     = contains(local.allowed, var.region) && contains(local.allowed, var.dr_region)
    error_message = "region/dr_region must both be inside the '${var.residency}' residency domain."
  }
}

data "aws_availability_zones" "available" { state = "available" }

# ---------------------------------------------------------------- network
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = var.name
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 200 + i)]
  database_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 210 + i)]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true # AZ-independent egress (cost: see docs/COST.md)
  enable_dns_hostnames   = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1, "karpenter.sh/discovery" = var.name }
  tags                = local.tags
}

# ---------------------------------------------------------------- Kubernetes
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access           = true # restrict with cidrs in prod (see variables in stacks)
  enable_cluster_creator_admin_permissions = true
  cluster_encryption_config                = { resources = ["secrets"] }
  enable_irsa                              = true

  # Small fixed managed node group for system components; everything else is Karpenter.
  eks_managed_node_groups = {
    system = {
      instance_types = [local.preset.node_type]
      min_size       = local.preset.min_nodes
      max_size       = local.preset.min_nodes + 2
      desired_size   = local.preset.min_nodes
      labels         = { role = "system" }
      taints         = {} # system pods tolerate; app pods go to Karpenter pools
    }
  }
  node_security_group_tags = { "karpenter.sh/discovery" = var.name }
  tags                     = local.tags
}

# ---------------------------------------------------------------- Postgres: Aurora Serverless v2
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_kms_key" "data" {
  description         = "${var.name} data at rest"
  enable_key_rotation = true
  tags                = local.tags
}

resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  tags = local.tags
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = module.vpc.database_subnets
}

resource "aws_rds_cluster" "pg" {
  cluster_identifier              = var.name
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned" # required for serverless v2
  engine_version                  = "16.4"
  database_name                   = "app"
  master_username                 = "app_admin"
  master_password                 = random_password.db.result
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.data.arn
  backup_retention_period         = 14 # PITR window
  preferred_backup_window         = "01:00-02:00"
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = local.preset.min_acu
    max_capacity = local.max_acu
  }
  tags = local.tags
}

resource "aws_rds_cluster_instance" "pg" {
  count                = 2 # writer + reader in different AZs; reader promotion_tier 0 = fast failover
  identifier           = "${var.name}-${count.index}"
  cluster_identifier   = aws_rds_cluster.pg.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.pg.engine
  engine_version       = aws_rds_cluster.pg.engine_version
  promotion_tier       = 0
  db_subnet_group_name = aws_db_subnet_group.this.name
  tags                 = local.tags
}

# ---------------------------------------------------------------- Redis
resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-redis-"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  tags = local.tags
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = module.vpc.database_subnets
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = var.name
  description                = "${var.name} job queue"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = local.preset.redis
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis.result
  snapshot_retention_limit   = 7
  tags                       = local.tags
}

# ---------------------------------------------------------------- Secrets (names only leave this module)
resource "aws_secretsmanager_secret" "db" {
  name       = "${var.name}/postgres"
  kms_key_id = aws_kms_key.data.arn
  tags       = local.tags
}
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host = aws_rds_cluster.pg.endpoint, port = 5432, dbname = "app",
    username = "app_admin", password = random_password.db.result
  })
}
resource "aws_secretsmanager_secret" "redis" {
  name       = "${var.name}/redis"
  kms_key_id = aws_kms_key.data.arn
  tags       = local.tags
}
resource "aws_secretsmanager_secret_version" "redis" {
  secret_id     = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({ host = aws_elasticache_replication_group.redis.primary_endpoint_address, port = 6379, address = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379", password = random_password.redis.result })
}

# ---------------------------------------------------------------- Workload identity (IRSA)
module "irsa_eso" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                      = "${var.name}-external-secrets"
  attach_external_secrets_policy = true
  external_secrets_secrets_manager_arns = [
    aws_secretsmanager_secret.db.arn, aws_secretsmanager_secret.redis.arn
  ]
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true
  enable_irsa           = true
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn
  create_pod_identity_association = false
  tags                  = local.tags
}
