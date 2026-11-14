################################################################################
# GitHub Actions -> Azure via OIDC (workload identity federation). No client
# secrets: each workflow exchanges its GitHub OIDC token for an Entra ID token
# of a user-assigned managed identity whose federated credential matches the
# token's subject exactly.
#
#  identity              | federated subjects                         | Azure RBAC
#  ----------------------|--------------------------------------------|------------------------------------------
#  <project>-gha-tf-plan | pull_request, main branch                  | Reader (subscription) + state blobs
#  <project>-gha-tf-apply| GitHub Environments dev / prod only        | Contributor + RBAC Administrator (*) + state
#  <project>-gha-ci      | main branch + environments                 | AcrPush; AKS access granted by each stack
#
# (*) Needed to create role assignments for workload identities. In a real
#     enterprise subscription constrain it with an ABAC condition or use a
#     dedicated landing-zone subscription.
################################################################################

variable "project" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "environments" { type = list(string) }
variable "subscription_id" { type = string } # full resource id: /subscriptions/<guid>
variable "tfstate_scope" { type = string }
variable "acr_id" { type = string }
variable "tags" { type = map(string) }

locals {
  repo   = "${var.github_org}/${var.github_repo}"
  issuer = "https://token.actions.githubusercontent.com"

  env_subjects = { for e in var.environments : "env-${e}" => "repo:${local.repo}:environment:${e}" }

  identities = {
    "tf-plan" = {
      subjects = {
        pull-request = "repo:${local.repo}:pull_request"
        main         = "repo:${local.repo}:ref:refs/heads/main"
      }
      roles = [
        { scope = var.subscription_id, role = "Reader" },
        { scope = var.tfstate_scope, role = "Storage Blob Data Contributor" }, # blob lease = state lock
      ]
    }
    "tf-apply" = {
      subjects = local.env_subjects
      roles = [
        { scope = var.subscription_id, role = "Contributor" },
        { scope = var.subscription_id, role = "Role Based Access Control Administrator" },
        { scope = var.tfstate_scope, role = "Storage Blob Data Contributor" },
      ]
    }
    "ci" = {
      subjects = merge({ main = "repo:${local.repo}:ref:refs/heads/main" }, local.env_subjects)
      roles = [
        { scope = var.acr_id, role = "AcrPush" },
      ]
    }
  }

  # Azure rejects concurrent federated-credential writes on the SAME identity
  # (HTTP 409), so credentials are created in tiers: tier n waits for tier n-1.
  credentials = merge([
    for id, cfg in local.identities : {
      for i, k in sort(keys(cfg.subjects)) : "${id}/${k}" => { identity = id, name = k, subject = cfg.subjects[k], tier = i }
    }
  ]...)

  assignments = merge([
    for id, cfg in local.identities : {
      for i, r in cfg.roles : "${id}/${i}" => merge(r, { identity = id })
    }
  ]...)
}

resource "azurerm_user_assigned_identity" "this" {
  for_each            = local.identities
  name                = "${var.project}-gha-${each.key}"
  resource_group_name = var.resource_group
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "tier0" {
  for_each                  = { for k, v in local.credentials : k => v if v.tier == 0 }
  name                      = "github-${each.value.name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  issuer                    = local.issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = each.value.subject
}

resource "azurerm_federated_identity_credential" "tier1" {
  for_each                  = { for k, v in local.credentials : k => v if v.tier == 1 }
  name                      = "github-${each.value.name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  issuer                    = local.issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = each.value.subject
  depends_on                = [azurerm_federated_identity_credential.tier0]
}

resource "azurerm_federated_identity_credential" "tier2" {
  for_each                  = { for k, v in local.credentials : k => v if v.tier >= 2 }
  name                      = "github-${each.value.name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  issuer                    = local.issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = each.value.subject
  depends_on                = [azurerm_federated_identity_credential.tier1]
}

resource "azurerm_role_assignment" "this" {
  for_each             = local.assignments
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.this[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
}

output "client_ids" {
  value = { for k, v in azurerm_user_assigned_identity.this : k => v.client_id }
}

output "principal_ids" {
  value = { for k, v in azurerm_user_assigned_identity.this : k => v.principal_id }
}
