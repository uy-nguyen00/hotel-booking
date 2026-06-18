#!/usr/bin/env bash
set -euo pipefail

readonly TRAEFIK_CHART_VERSION="41.0.0"
readonly GATEWAY_API_VERSION="1.5.1"
readonly TRAEFIK_NAMESPACE="traefik"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
environment="${1:-}"

case "$environment" in
  local|prod)
    ;;
  *)
    echo "usage: $0 local|prod" >&2
    exit 64
    ;;
esac

values_dir="$repo_root/k8s/traefik"
gateway_api_url="https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GATEWAY_API_VERSION}/standard-install.yaml"

kubectl apply -f "$gateway_api_url"
kubectl apply -f "$values_dir/gateway-class.yaml"

helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update traefik
helm upgrade --install traefik traefik/traefik \
  --version "$TRAEFIK_CHART_VERSION" \
  --namespace "$TRAEFIK_NAMESPACE" \
  --create-namespace \
  -f "$values_dir/values-common.yaml" \
  -f "$values_dir/values-${environment}.yaml"

kubectl rollout status deployment/traefik \
  --namespace "$TRAEFIK_NAMESPACE" \
  --timeout=180s
kubectl wait gatewayclass/traefik \
  --for=condition=Accepted \
  --timeout=120s
