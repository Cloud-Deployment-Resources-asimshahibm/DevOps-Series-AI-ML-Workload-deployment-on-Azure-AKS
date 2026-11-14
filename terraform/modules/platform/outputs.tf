output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "postgres_service" {
  value = "platform-postgres.platform-system.svc.cluster.local"
}
