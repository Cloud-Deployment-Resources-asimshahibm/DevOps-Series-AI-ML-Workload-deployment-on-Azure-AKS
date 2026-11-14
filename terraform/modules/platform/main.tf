################################################################################
# Day-0 platform installed by Terraform — only what must exist BEFORE GitOps:
#   RWX storage class, Postgres service alias, Argo CD + the root app-of-apps.
# Already provided by AKS: metrics-server, Azure Disk/File CSI drivers,
# node auto-provisioning (Karpenter), Workload ID webhook, AGIC ingress.
# Everything else (JupyterHub, Argo Workflows, KubeRay, Prometheus, Grafana,
# Loki, ELK, GPU operator, ML apps) is delivered by Argo CD from Git.
################################################################################

# ------------------------------------------------------------------------------
# Storage classes. Block storage uses the AKS built-ins (managed-csi,
# managed-csi-premium). RWX (the AWS EFS equivalent) = Azure Files NFS, Premium:
# the CSI driver creates a Premium FileStorage account in the node resource group,
# reachable only from the cluster VNet.
# ------------------------------------------------------------------------------
resource "kubernetes_storage_class_v1" "azurefile_nfs" {
  metadata {
    name = "azurefile-nfs"
  }
  storage_provisioner    = "file.csi.azure.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true
  parameters = {
    protocol = "nfs"
    skuName  = "Premium_ZRS"
    # cost allocation tags on the storage account the driver creates
    tags = "Project=${var.project},Environment=${var.environment},ManagedBy=azurefile-csi"
  }
  mount_options = ["nconnect=4", "noresvport", "actimeo=30"]
}

# ------------------------------------------------------------------------------
# Stable in-cluster DNS name for PostgreSQL so Git never contains the server FQDN:
#   platform-postgres.platform-system.svc.cluster.local -> <server>.postgres.database.azure.com
# (resolved through the private DNS zone linked to the VNet)
# ------------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "platform_system" {
  metadata {
    name   = "platform-system"
    labels = { "app.kubernetes.io/part-of" = "ml-platform" }
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "platform-postgres"
    namespace = kubernetes_namespace_v1.platform_system.metadata[0].name
  }
  spec {
    type          = "ExternalName"
    external_name = var.postgres_fqdn
    port {
      port = 5432
    }
  }
}

# ------------------------------------------------------------------------------
# Argo CD
# ------------------------------------------------------------------------------
locals {
  # Argo CD >= 1.8 does not assess Application health by default; without this
  # sync-waves in the app-of-apps would not wait for child apps to be Healthy.
  app_health_lua = <<-EOT
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
  EOT
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    global = {
      nodeSelector = { workload = "system" }
    }
    configs = {
      params = {
        "server.insecure" = true # TLS terminates at the Application Gateway / port-forward
      }
      cm = {
        "timeout.reconciliation"                                 = "120s"
        "resource.customizations.health.argoproj.io_Application" = local.app_health_lua
        "statusbadge.enabled"                                    = "true"
      }
    }
    redis-ha = { enabled = var.argocd_ha }
    controller = {
      replicas = var.argocd_ha ? 2 : 1
      metrics  = { enabled = true }
    }
    server = {
      replicas = var.argocd_ha ? 2 : 1
      metrics  = { enabled = true }
    }
    repoServer = {
      replicas = var.argocd_ha ? 2 : 1
      metrics  = { enabled = true }
    }
    applicationSet = { replicas = var.argocd_ha ? 2 : 1 }
  })]
}

# ------------------------------------------------------------------------------
# GitOps bootstrap: ONE root Application (Helm chart argocd/app-of-apps rendered
# with values-<env>.yaml + the `cloud` facts below) -> everything else from Git.
# ------------------------------------------------------------------------------
resource "helm_release" "argocd_root_app" {
  count = var.bootstrap_gitops ? 1 : 0

  name       = "argocd-root-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.chart_versions.argocd_apps
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      "root-${var.environment}" = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "argocd/app-of-apps"
          helm = {
            valueFiles   = ["values.yaml", "values-${var.environment}.yaml"]
            valuesObject = { cloud = var.cloud }
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
