variable "subscription_id" {
  description = "Azure subscription that hosts the platform (scripts/configure.sh renders it)."
  type        = string
}

variable "location" {
  description = "Azure region for shared resources (state, ACR)."
  type        = string
  default     = "eastus2"
}

variable "project" {
  description = "Short project prefix used in every resource name."
  type        = string
  default     = "aiml"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org)."
  type        = string
}

variable "environments" {
  description = "GitHub Environments allowed to use the apply identity."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "acr_sku" {
  description = "Basic | Standard | Premium. Premium adds private endpoints, geo-replication, retention."
  type        = string
  default     = "Standard"
}

variable "billing_alert_emails" {
  description = "Recipients of subscription-level cost anomaly alerts."
  type        = list(string)
  default     = []
}
