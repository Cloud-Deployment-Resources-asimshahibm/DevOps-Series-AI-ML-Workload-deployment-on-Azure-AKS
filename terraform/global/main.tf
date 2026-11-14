################################################################################
# GLOBAL LAYER (once per subscription)
#
#   - Resource group <project>-global-rg
#   - Storage account for Terraform state (Entra ID auth only, versioned,
#     soft delete; Terraform locks state with blob leases)
#   - Azure Container Registry shared by all environments (build once, promote everywhere)
#   - GitHub Actions -> Azure via OIDC: three user-assigned managed identities
#     with federated credentials (no client secrets anywhere)
#   - Subscription cost anomaly alert
################################################################################

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  # Globally unique names (storage, ACR) get a stable 6-char suffix derived
  # from the subscription id. scripts/configure.sh computes the same value.
  suffix = substr(sha1(var.subscription_id), 0, 6)
  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Layer     = "global"
  }
}

resource "azurerm_resource_group" "global" {
  name     = "${var.project}-global-rg"
  location = var.location
  tags     = local.tags
}

# ------------------------------------------------------------------------------
# Terraform state
# ------------------------------------------------------------------------------
resource "azurerm_storage_account" "tfstate" {
  name                            = "${var.project}tfstate${local.suffix}"
  resource_group_name             = azurerm_resource_group.global.name
  location                        = azurerm_resource_group.global.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false # Entra ID (RBAC) only
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# whoever runs the bootstrap needs data-plane access to migrate state
resource "azurerm_role_assignment" "tfstate_bootstrap" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ------------------------------------------------------------------------------
# Container registry
# ------------------------------------------------------------------------------
resource "azurerm_container_registry" "this" {
  name                = "${var.project}${local.suffix}acr"
  resource_group_name = azurerm_resource_group.global.name
  location            = azurerm_resource_group.global.location
  sku                 = var.acr_sku
  admin_enabled       = false # pulls via kubelet identity, pushes via GitHub OIDC
  tags                = local.tags
}

# ------------------------------------------------------------------------------
# GitHub OIDC identities
# ------------------------------------------------------------------------------
module "github_oidc" {
  source = "../modules/github-oidc"

  project         = var.project
  location        = var.location
  resource_group  = azurerm_resource_group.global.name
  github_org      = var.github_org
  github_repo     = var.github_repo
  environments    = var.environments
  subscription_id = data.azurerm_subscription.current.id
  tfstate_scope   = azurerm_storage_account.tfstate.id
  acr_id          = azurerm_container_registry.this.id
  tags            = local.tags
}

# ------------------------------------------------------------------------------
# Billing: subscription-wide anomaly alert (budgets are per environment, see stack)
# ------------------------------------------------------------------------------
resource "azurerm_cost_anomaly_alert" "this" {
  count           = length(var.billing_alert_emails) > 0 ? 1 : 0
  name            = "${var.project}-cost-anomaly"
  display_name    = "${var.project} cost anomaly"
  subscription_id = data.azurerm_subscription.current.id
  email_subject   = "[${var.project}] Azure cost anomaly detected"
  email_addresses = var.billing_alert_emails
}
