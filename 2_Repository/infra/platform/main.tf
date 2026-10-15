# Platform layer: identical on every provider. Only the *inputs* differ (see provider/CONTRACT.md).
# Installed by Terraform once (bootstrap); afterwards Argo CD owns the application layer.
terraform {
  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 2.15" }
  }
}

locals {
  ns = { for n in ["ingress", "argocd", "argo-rollouts", "keda", "monitoring", "external-secrets", "kyverno"] : n => n }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.4"
  values = [yamlencode({
    serviceAccount = {
      annotations = lookup(var.workload_identity, "external_secrets", null) == null ? {} : {
        "eks.amazonaws.com/role-arn" = var.workload_identity["external_secrets"]
      }
    }
  })]
}

resource "helm_release" "ingress" {
  name             = "ingress-nginx"
  namespace        = "ingress"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.2"
  values = [yamlencode({
    controller = merge({
      replicaCount        = 3
      service             = { annotations = var.ingress_service_annotations }
      metrics             = { enabled = true, serviceMonitor = { enabled = true } }
      podDisruptionBudget = { enabled = true, minAvailable = 2 }
      config              = { "use-forwarded-headers" = "true" }
      }, var.ingress_local_mode ? {
      replicaCount        = 1
      hostPort            = { enabled = true }
      service             = { type = "NodePort" }
      podDisruptionBudget = { enabled = false }
      nodeSelector        = { "ingress-ready" = "true" }
      tolerations         = [{ key = "node-role.kubernetes.io/control-plane", operator = "Equal", effect = "NoSchedule" }]
    } : {})
  })]
  depends_on = [helm_release.kube_prometheus]
}

resource "helm_release" "keda" {
  name             = "keda"
  namespace        = "keda"
  create_namespace = true
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.15.1"
}

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = "2.37.7"
  values = [yamlencode({
    controller = { metrics = { enabled = true, serviceMonitor = { enabled = true } } }
  })]
  depends_on = [helm_release.kube_prometheus]
}

resource "helm_release" "kube_prometheus" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.1.1"
  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention                               = "15d"
        serviceMonitorSelectorNilUsesHelmValues = false
        ruleSelectorNilUsesHelmValues           = false
        externalLabels                          = { tenant = var.tenant_label, ring = var.ring, cluster = var.cluster_name, region = var.region }
        remoteWrite                             = var.remote_write_url == "" ? [] : [{ url = var.remote_write_url }]
        storageSpec = { volumeClaimTemplate = { spec = {
          storageClassName = var.storage_class
          resources        = { requests = { storage = "100Gi" } }
        } } }
      }
    }
    grafana = { sidecar = { dashboards = { enabled = true, searchNamespace = "ALL" } } }
  })]
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = "2.10.2"
  values     = [yamlencode({ loki = { persistence = { enabled = true, storageClassName = var.storage_class, size = "50Gi" } }, promtail = { enabled = true } })]
  depends_on = [helm_release.kube_prometheus]
}

resource "helm_release" "kyverno" {
  count            = var.enable_kyverno ? 1 : 0
  name             = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  version          = "3.2.7"
}

# Argo CD last: it brings this cluster's own app + platform-config (pull-based CD, no inbound creds)
resource "helm_release" "argocd" {
  count            = var.enable_argocd ? 1 : 0
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.8"
  values = [yamlencode({
    configs = { params = { "server.insecure" = true } }
    controller = { metrics = { enabled = true } }
    extraObjects = [
      {
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "Application"
        metadata   = { name = "platform-config", namespace = "argocd" }
        spec = {
          project     = "default"
          source      = { repoURL = var.gitops_repo, targetRevision = var.gitops_revision, path = "gitops/platform/${var.autoscaler}"
          helm = { parameters = [
            { name = "clusterName", value = var.cluster_name },
            { name = "region", value = var.region },
            { name = "nodeRole", value = lookup(var.workload_identity, "karpenter_node", "") },
            { name = "secretStoreKind", value = var.secret_store_kind },
          ] } }
          destination = { server = "https://kubernetes.default.svc", namespace = "kube-system" }
          syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["ServerSideApply=true"] }
        }
      },
      {
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "Application"
        metadata   = { name = "app-root", namespace = "argocd" }
        spec = {
          project     = "default"
          source      = { repoURL = var.gitops_repo, targetRevision = var.gitops_revision, path = var.cluster_gitops_dir, directory = { include = "application.yaml" } }
          destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
          syncPolicy  = { automated = { prune = true, selfHeal = true } }
        }
      }
    ]
  })]
  depends_on = [helm_release.keda, helm_release.argo_rollouts, helm_release.external_secrets, helm_release.kube_prometheus]
}
