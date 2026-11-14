variable "environment" { type = string }
variable "project" { type = string }
variable "postgres_fqdn" { type = string }

variable "cloud" {
  description = <<-EOT
    Azure facts that GitOps needs but Git cannot know (generated ids and names).
    Passed to the root app-of-apps as `cloud:` and templated into each child
    Application (cloudValues), so nothing is copied into Git by hand.
  EOT
  type        = any
}

variable "gitops_repo_url" {
  description = "HTTPS URL of this repository; Argo CD syncs from it."
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "bootstrap_gitops" {
  description = "Create the Argo CD root (app-of-apps) Application."
  type        = bool
  default     = true
}

variable "argocd_ha" {
  description = "Run Argo CD in HA mode (recommended for prod)."
  type        = bool
  default     = false
}

# Pinned chart versions = reproducible platform. Bump them via PR, never `latest`.
variable "chart_versions" {
  type = object({
    argo_cd     = string
    argocd_apps = string
  })
  default = {
    argo_cd     = "7.7.10"
    argocd_apps = "2.0.2"
  }
}
