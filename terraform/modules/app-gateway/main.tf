################################################################################
# Application Gateway v2 for ingress. The AKS add-on AGIC (Application Gateway
# Ingress Controller) owns its listeners, pools, probes and rules: it rewrites
# them from Kubernetes Ingress objects. Terraform only creates the gateway with
# a placeholder configuration and then ignores those blocks.
################################################################################

variable "name" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "subnet_id" { type = string }
variable "zones" {
  type    = list(string)
  default = []
}
variable "min_capacity" {
  type    = number
  default = 1
}
variable "max_capacity" {
  type    = number
  default = 3
}
variable "sku" {
  description = "Standard_v2, or WAF_v2 together with firewall_policy_id."
  type        = string
  default     = "Standard_v2"
}
variable "firewall_policy_id" {
  type    = string
  default = null
}
variable "tags" { type = map(string) }

locals {
  fe_ip    = "public"
  fe_port  = "http"
  pool     = "placeholder"
  settings = "placeholder"
  listener = "placeholder"
}

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-appgw-pip"
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  domain_name_label   = "${var.name}-ml" # <label>.<region>.cloudapp.azure.com
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {
  name                = "${var.name}-appgw"
  location            = var.location
  resource_group_name = var.resource_group
  zones               = var.zones
  firewall_policy_id  = var.firewall_policy_id
  http2_enabled       = true
  tags                = var.tags

  sku {
    name = var.sku
    tier = var.sku
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S" # TLS 1.2+ only
  }

  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = local.fe_ip
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = local.fe_port
    port = 80
  }

  backend_address_pool {
    name = local.pool
  }

  backend_http_settings {
    name                  = local.settings
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener
    frontend_ip_configuration_name = local.fe_ip
    frontend_port_name             = local.fe_port
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "placeholder"
    priority                   = 19500
    rule_type                  = "Basic"
    http_listener_name         = local.listener
    backend_address_pool_name  = local.pool
    backend_http_settings_name = local.settings
  }

  # AGIC manages these from Ingress objects
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      redirect_configuration,
      request_routing_rule,
      rewrite_rule_set,
      ssl_certificate,
      url_path_map,
      tags,
    ]
  }
}

output "id" { value = azurerm_application_gateway.this.id }
output "name" { value = azurerm_application_gateway.this.name }
output "public_ip" { value = azurerm_public_ip.this.ip_address }
output "fqdn" { value = azurerm_public_ip.this.fqdn }
