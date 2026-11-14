################################################################################
# Billing guardrails for one environment (Azure Cost Management budgets)
#
#   <name>-total    everything tagged Project=<project>, Environment=<env>
#                   (AKS propagates cluster tags to the node resource group;
#                   NAP nodes get them from the AKSNodeClass)
#   <name>-compute  the same scope, Virtual Machines meter category only
#
# Alerts: 80 % and 100 % of actual spend, 100 % of forecast.
# The subscription-wide cost anomaly alert lives in terraform/global.
################################################################################

variable "name" { type = string }
variable "project" { type = string }
variable "environment" { type = string }
variable "subscription_id" { type = string } # /subscriptions/<guid>
variable "monthly_budget_usd" { type = number }
variable "compute_budget_usd" { type = number }
variable "alert_emails" { type = list(string) }

locals {
  budgets = {
    total   = { amount = var.monthly_budget_usd, meter_categories = [] }
    compute = { amount = var.compute_budget_usd, meter_categories = ["Virtual Machines"] }
  }
  notifications = [
    { threshold = 80, type = "Actual" },
    { threshold = 100, type = "Actual" },
    { threshold = 100, type = "Forecasted" },
  ]
  # budgets need a first-of-month start date; keep it stable after creation
  start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
}

resource "azurerm_consumption_budget_subscription" "this" {
  for_each        = length(var.alert_emails) > 0 ? local.budgets : {}
  name            = "${var.name}-${each.key}"
  subscription_id = var.subscription_id
  amount          = each.value.amount
  time_grain      = "Monthly"

  time_period {
    start_date = local.start_date
  }

  filter {
    tag {
      name   = "Project"
      values = [var.project]
    }
    tag {
      name   = "Environment"
      values = [var.environment]
    }
    dynamic "dimension" {
      for_each = length(each.value.meter_categories) > 0 ? [1] : []
      content {
        name   = "MeterCategory"
        values = each.value.meter_categories
      }
    }
  }

  dynamic "notification" {
    for_each = local.notifications
    content {
      enabled        = true
      threshold      = notification.value.threshold
      threshold_type = notification.value.type
      operator       = "GreaterThan"
      contact_emails = var.alert_emails
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}

output "budget_names" {
  value = [for b in azurerm_consumption_budget_subscription.this : b.name]
}
