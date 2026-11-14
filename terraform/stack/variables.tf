variable "subscription_id" {
  type = string
}

variable "project" {
  type    = string
  default = "aiml"
}

variable "environment" {
  description = "dev | prod"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region. Pick one with GPU (NCads A10 / NC A100) quota for your subscription."
  type        = string
  default     = "eastus2"
}

variable "zones" {
  description = "Availability zones for the system pool, App Gateway and zone-redundant services."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "gitops_repo_url" {
  description = "HTTPS clone URL of this repo, used by Argo CD."
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

# ----------------------------- network -----------------------------
variable "vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "storage_allowed_ip_ranges" {
  description = "Public IPs/CIDRs (office/VPN) allowed through the storage firewall, e.g. to browse blobs."
  type        = list(string)
  default     = []
}

# ----------------------------- cluster -----------------------------
variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "aks_sku_tier" {
  description = "Free (dev) | Standard (prod: financially backed API server SLA)."
  type        = string
  default     = "Free"
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server. Empty = any. Lock to office/VPN egress (+ GitHub runners or self-hosted runners)."
  type        = list(string)
  default     = []
}

variable "cluster_admin_object_ids" {
  description = "Entra ID object ids (users or groups) granted AKS RBAC Cluster Admin. scripts/configure.sh adds yours."
  type        = list(string)
  default     = []
}

variable "system_node_pool" {
  description = "AKS-managed pool for controllers (Argo CD, AGIC, CoreDNS, ...). ML capacity comes from node auto-provisioning."
  type = object({
    vm_size    = string
    node_count = number
  })
  default = {
    vm_size    = "Standard_D4ds_v5"
    node_count = 2
  }
}

# ----------------------------- ingress -----------------------------
variable "app_gateway" {
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = {
    min_capacity = 1
    max_capacity = 3
  }
}

# ----------------------------- database -----------------------------
variable "postgres" {
  type = object({
    sku_name              = string
    storage_mb            = number
    high_availability     = bool
    backup_retention_days = number
    geo_redundant_backup  = bool
  })
  default = {
    sku_name              = "B_Standard_B2s"
    storage_mb            = 32768
    high_availability     = false
    backup_retention_days = 7
    geo_redundant_backup  = false
  }
}

# ----------------------------- security -----------------------------
variable "key_vault_purge_protection" {
  description = "true for prod (cannot be turned off again)."
  type        = bool
  default     = false
}

# ----------------------------- gitops -----------------------------
variable "argocd_ha" {
  type    = bool
  default = false
}

variable "bootstrap_gitops" {
  type    = bool
  default = true
}

# ----------------------------- billing -----------------------------
variable "budgets" {
  description = "Monthly Cost Management budgets for this environment (USD). Alerts at 80%/100% actual and 100% forecast."
  type = object({
    monthly_total_usd   = number
    monthly_compute_usd = number
    alert_emails        = list(string)
  })
  default = {
    monthly_total_usd   = 900
    monthly_compute_usd = 550
    alert_emails        = []
  }
}
