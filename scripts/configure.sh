#!/usr/bin/env bash
# Render subscription-specific placeholders across the repo, then commit the result.
#
#   __SUBSCRIPTION_ID__          -> your Azure subscription id
#   __ADMIN_OBJECT_ID__          -> Entra ID object id of the person running this (AKS cluster-admin)
#   __TFSTATE_STORAGE_ACCOUNT__  -> aimltfstate<suffix> (suffix = first 6 hex of sha1(subscription id),
#                                   the same value terraform/global computes)
#
# Usage: scripts/configure.sh [--subscription-id <guid>] [--admin-object-id <guid>] [--project aiml]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SUB=""
ADMIN=""
PROJECT="aiml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id) SUB="$2"; shift 2 ;;
    --admin-object-id) ADMIN="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    *) echo "unknown arg $1"; exit 1 ;;
  esac
done

SUB=${SUB:-$(az account show --query id -o tsv)}
ADMIN=${ADMIN:-$(az ad signed-in-user show --query id -o tsv)}
GUID='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
[[ "$SUB" =~ $GUID ]] || { echo "invalid subscription id: $SUB"; exit 1; }
[[ "$ADMIN" =~ $GUID ]] || { echo "invalid admin object id: $ADMIN"; exit 1; }

SUFFIX=$(printf '%s' "$SUB" | sha1sum | cut -c1-6)
STATE_SA="${PROJECT}tfstate${SUFFIX}"

echo "Subscription     : $SUB"
echo "Admin object id  : $ADMIN"
echo "Name suffix      : $SUFFIX  (state account $STATE_SA, ACR ${PROJECT}${SUFFIX}acr)"

FILES=$(grep -rlE '__SUBSCRIPTION_ID__|__ADMIN_OBJECT_ID__|__TFSTATE_STORAGE_ACCOUNT__' \
  --include='*.yaml' --include='*.yml' --include='*.tf' --include='*.tfvars' --include='*.example' --include='*.hcl' \
  --exclude-dir=.git --exclude-dir=docs . || true)

for f in $FILES; do
  sed -i.bak -e "s|__SUBSCRIPTION_ID__|${SUB}|g" -e "s|__ADMIN_OBJECT_ID__|${ADMIN}|g" \
    -e "s|__TFSTATE_STORAGE_ACCOUNT__|${STATE_SA}|g" "$f" && rm -f "$f.bak"
  echo "  rendered $f"
done

echo
echo "Done. Review with 'git diff', then commit + push so CI and Argo CD see the real values:"
echo "  git commit -am 'chore: configure subscription' && git push"
