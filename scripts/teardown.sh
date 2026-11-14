#!/usr/bin/env bash
# Destroy an environment safely. Order matters: remove the Kubernetes objects
# that own Azure resources (Application Gateway rules, Azure Disk / Files
# volumes, auto-provisioned VMs) BEFORE Terraform destroys the cluster and VNet.
set -euo pipefail
ENV=${1:?usage: teardown.sh dev|prod}
ROOT=$(git rev-parse --show-toplevel)
read -r -p "This DESTROYS aiml-$ENV (cluster, PostgreSQL, storage account, Key Vault). Type the env name to confirm: " c
[[ "$c" == "$ENV" ]] || { echo aborted; exit 1; }

echo ">> 1. Delete the root app (cascades all Argo CD apps + their resources)"
kubectl -n argocd delete applications.argoproj.io "root-$ENV" --wait=true --timeout=15m || true

echo ">> 2. Remove leftover ingresses / LoadBalancer services"
kubectl delete ingress -A --all --wait=true --timeout=5m || true
kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read -r ns n; do kubectl -n "$ns" delete svc "$n"; done

echo ">> 3. Release auto-provisioned capacity (node auto-provisioning NodePools)"
kubectl delete nodepools.karpenter.sh --all --wait=true --timeout=10m || true

echo ">> 4. terraform destroy"
cd "$ROOT/terraform/stack"
terraform init -input=false -reconfigure -backend-config="../envs/$ENV/backend.hcl"
terraform destroy -var-file="../envs/$ENV/terraform.tfvars"

echo "Done. Azure Files volumes use reclaimPolicy=Retain (premium file storage account in the"
echo "node resource group is removed with it). Key Vault stays soft-deleted for its retention"
echo "period (purge protection in prod): 'az keyvault purge' only if you really mean it."
