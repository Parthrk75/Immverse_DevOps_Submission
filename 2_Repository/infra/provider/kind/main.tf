# Local provider: kind cluster + in-cluster Postgres and Redis standing in for managed services.
# Same outputs as provider/aws (see ../CONTRACT.md). Not portable: no cloud LB, IAM or autoscaler.
resource "kind_cluster" "this" {
  name           = var.name
  wait_for_ready = true
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    # images pushed to localhost:5001 (scripts/local.sh registry) are pulled by containerd from kind-registry:5000
    containerd_config_patches = [<<-TOML
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
        endpoint = ["http://kind-registry:5000"]
    TOML
    ]
    node {
      role = "control-plane"
      kubeadm_config_patches = ["kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"]
      extra_port_mappings {
        container_port = 80
        host_port      = 8080
      }
    }
    node { role = "worker" }
    node { role = "worker" }
    node { role = "worker" }
  }
}

# NOTE: provider block inside a module is legacy style; kept so the kind module is self-contained.
provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
  }
}

resource "helm_release" "postgres" {
  name             = "postgres"
  namespace        = "data"
  create_namespace = true
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "postgresql"
  version          = "16.2.1"
  set {
    name  = "auth.database"
    value = "app"
  }
  set {
    name  = "auth.postgresPassword"
    value = "local-only-password"
  }
}

resource "helm_release" "redis" {
  name       = "redis"
  namespace  = "data"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "redis"
  version    = "20.2.1"
  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "auth.enabled"
    value = "false"
  }
  depends_on = [helm_release.postgres]
}
