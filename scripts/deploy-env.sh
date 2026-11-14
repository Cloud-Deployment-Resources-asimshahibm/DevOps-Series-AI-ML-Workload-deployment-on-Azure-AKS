#!/usr/bin/env bash
# Phase 4: provision one environment (dev|prod) end-to-end with Terraform.
# Terraform also installs Argo CD and the root app, after which Argo CD
# deploys everything else from Git.
set -euo pipefail
ENV=${1:?usage: deploy-env.sh dev|prod}
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT/terraform/stack"

if grep -q "__TFSTATE_STORAGE_ACCOUNT__\|__SUBSCRIPTION_ID__" "../envs/$ENV/backend.hcl" "../envs/$ENV/terraform.tfvars"; then
  echo "Placeholders not rendered. Run scripts/configure.sh first."; exit 1
fi
command -v kubelogin >/dev/null || { echo "kubelogin is required (az aks install-cli)"; exit 1; }

terraform init -input=false -reconfigure -backend-config="../envs/$ENV/backend.hcl"
terraform plan -input=false -var-file="../envs/$ENV/terraform.tfvars" -out="tfplan-$ENV"
read -r -p "Apply this plan to $ENV? [y/N] " ok
[[ "$ok" == "y" ]] || { echo "aborted"; exit 1; }
terraform apply -input=false "tfplan-$ENV"

RG=$(terraform output -raw resource_group)
CLUSTER=$(terraform output -raw cluster_name)
az aks get-credentials --resource-group "$RG" --name "$CLUSTER" --overwrite-existing --context "$CLUSTER"
kubelogin convert-kubeconfig -l azurecli

echo
echo ">> Waiting for Argo CD to sync the platform (this takes 10-20 min on first run)"
"$ROOT/scripts/wait-for-apps.sh" "$CLUSTER"
