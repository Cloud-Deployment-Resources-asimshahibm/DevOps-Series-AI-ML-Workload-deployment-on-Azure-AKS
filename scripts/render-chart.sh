#!/usr/bin/env bash
# Render one of our local charts exactly as Argo CD does:
#   values.yaml + values-<env>.yaml + the app's `cloudValues` (Azure facts)
# The cloudValues come from rendering argocd/app-of-apps — with the placeholder
# `cloud:` facts in its values.yaml (CI), or real ones (CLOUD_VALUES=<file>,
# e.g. from `terraform output`).
#
# usage: scripts/render-chart.sh values   <chart-dir> <env>             # print cloudValues
#        scripts/render-chart.sh template <chart-dir> <env> [helm args]  # helm template
#        scripts/render-chart.sh lint     <chart-dir> <env>             # helm lint
set -euo pipefail
CMD=${1:?usage: render-chart.sh values|template|lint <chart-dir> <env>}
CHART=${2:?chart dir}; ENV=${3:?env}; shift 3
cd "$(git rev-parse --show-toplevel)"
CHART=${CHART%/}
AOA=argocd/app-of-apps

cloud_values() {
  local app
  app=$(yq ".apps | to_entries | .[] | select(.value.path == \"$CHART\") | .key" "$AOA/values.yaml")
  if [[ -z "$app" ]]; then echo "{}"; return; fi
  helm template root "$AOA" -f "$AOA/values.yaml" -f "$AOA/values-$ENV.yaml" ${CLOUD_VALUES:+-f "$CLOUD_VALUES"} \
    | yq "select(.kind == \"Application\" and .metadata.name == \"$app\") | .spec.source.helm.valuesObject // {}"
}

EXTRA=$(mktemp)
trap 'rm -f "$EXTRA"' EXIT
cloud_values > "$EXTRA"

case "$CMD" in
  values)   cat "$EXTRA" ;;
  template) helm template "$(basename "$CHART")" "$CHART" -f "$CHART/values.yaml" -f "$CHART/values-$ENV.yaml" -f "$EXTRA" "$@" ;;
  lint)     helm lint "$CHART" -f "$CHART/values.yaml" -f "$CHART/values-$ENV.yaml" -f "$EXTRA" ;;
  *) echo "unknown command $CMD"; exit 1 ;;
esac
