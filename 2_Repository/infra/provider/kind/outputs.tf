output "cluster_name" { value = kind_cluster.this.name }
output "cluster_endpoint" { value = kind_cluster.this.endpoint }
output "cluster_ca_data" { value = base64encode(kind_cluster.this.cluster_ca_certificate) }
output "client_certificate" {
  value     = kind_cluster.this.client_certificate
  sensitive = true
}
output "client_key" {
  value     = kind_cluster.this.client_key
  sensitive = true
}
output "kube_exec" { value = null }
output "postgres_host" { value = "postgres-postgresql.data.svc.cluster.local" }
output "postgres_port" { value = 5432 }
output "postgres_secret_name" { value = "postgres" }
output "redis_host" { value = "redis-master.data.svc.cluster.local" }
output "redis_port" { value = 6379 }
output "redis_secret_name" { value = "redis" }
output "secret_store_kind" { value = "kubernetes" }
output "storage_class" { value = "standard" }
output "ingress_service_annotations" { value = {} }
output "workload_identity" { value = {} }
output "autoscaler" { value = "none" }
output "region" { value = "local" }
