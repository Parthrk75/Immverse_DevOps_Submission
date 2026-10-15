output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_ca_data" { value = module.eks.cluster_certificate_authority_data }
output "kube_exec" {
  value = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}
output "postgres_host" { value = aws_rds_cluster.pg.endpoint }
output "postgres_port" { value = 5432 }
output "postgres_secret_name" { value = aws_secretsmanager_secret.db.name }
output "redis_host" { value = aws_elasticache_replication_group.redis.primary_endpoint_address }
output "redis_port" { value = 6379 }
output "redis_secret_name" { value = aws_secretsmanager_secret.redis.name }
output "secret_store_kind" { value = "aws-secretsmanager" }
output "storage_class" { value = "gp3" }
output "ingress_service_annotations" {
  value = {
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
  }
}
output "workload_identity" {
  value = {
    external_secrets = module.irsa_eso.iam_role_arn
    karpenter        = module.karpenter.iam_role_arn
    karpenter_node   = module.karpenter.node_iam_role_name
    karpenter_queue  = module.karpenter.queue_name
  }
}
output "autoscaler" { value = "karpenter" }
output "region" { value = var.region }
