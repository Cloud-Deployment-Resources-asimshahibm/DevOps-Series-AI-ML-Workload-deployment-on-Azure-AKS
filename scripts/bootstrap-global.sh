#!/usr/bin/env bash
# Phase 2: create the shared layer (state storage account, ACR, GitHub OIDC
# identities) and migrate its own state into the storage account it just created.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/terraform/global"

[[ -f terraform.tfvars ]] || cp terraform.tfvars.example terraform.tfvars
grep -q "__SUBSCRIPTION_ID__" terraform.tfvars && { echo "Run scripts/configure.sh first (or edit terraform.tfvars)."; exit 1; }

echo ">> terraform apply (local state)"
terraform init -input=false
terraform apply -input=false

SA=$(terraform output -raw state_storage_account)
RG=$(terraform output -raw state_resource_group)

if [[ ! -f backend.tf ]]; then
  echo ">> waiting for the data-plane role assignment to propagate"
  for i in $(seq 1 30); do
    az storage container show --account-name "$SA" --name tfstate --auth-mode login >/dev/null 2>&1 && break
    sleep 10
  done
  echo ">> migrating global state to ${SA}/tfstate/global/terraform.tfstate"
  cat > backend.tf <<EOT
terraform {
  backend "azurerm" {
    resource_group_name  = "${RG}"
    storage_account_name = "${SA}"
    container_name       = "tfstate"
    key                  = "global/terraform.tfstate"
    use_azuread_auth     = true
  }
}
EOT
  terraform init -input=false -migrate-state -force-copy
  rm -f terraform.tfstate terraform.tfstate.backup
fi

echo
echo ">> Add these as GitHub repository *variables* (Settings > Secrets and variables > Actions > Variables):"
terraform output -json gha_variables | jq -r 'to_entries[] | "   \(.key) = \(.value)"'
echo
echo "   or: terraform output -json gha_variables | jq -r 'to_entries[] | \"\(.key) \(.value)\"' | while read k v; do gh variable set \$k --body \$v; done"
