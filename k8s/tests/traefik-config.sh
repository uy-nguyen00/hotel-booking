#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
traefik_dir="$repo_root/k8s/traefik"

grep -Fq 'TRAEFIK_CHART_VERSION="41.0.0"' "$traefik_dir/install.sh"
grep -Fq 'GATEWAY_API_VERSION="1.5.1"' "$traefik_dir/install.sh"
grep -Fq 'standard-install.yaml' "$traefik_dir/install.sh"
grep -Fq -- '--version "$TRAEFIK_CHART_VERSION"' "$traefik_dir/install.sh"

grep -Fq 'controllerName: traefik.io/gateway-controller' "$traefik_dir/gateway-class.yaml"
grep -Fq 'name: traefik' "$traefik_dir/gateway-class.yaml"

grep -Fq 'kubernetesGateway:' "$traefik_dir/values-common.yaml"
grep -Fq 'kubernetesIngress:' "$traefik_dir/values-common.yaml"
grep -Fq 'kubernetesCRD:' "$traefik_dir/values-common.yaml"
test "$(awk '/^  kubernetesGateway:$/ { getline; print $2 }' "$traefik_dir/values-common.yaml")" = true
test "$(awk '/^  kubernetesIngress:$/ { getline; print $2 }' "$traefik_dir/values-common.yaml")" = false
test "$(awk '/^  kubernetesCRD:$/ { getline; print $2 }' "$traefik_dir/values-common.yaml")" = false
test "$(grep -Fc 'enabled: false' "$traefik_dir/values-common.yaml")" -eq 5
test "$(grep -Fc 'enabled: true' "$traefik_dir/values-common.yaml")" -eq 1

grep -Fq 'replicas: 1' "$traefik_dir/values-local.yaml"
grep -Fq 'replicas: 2' "$traefik_dir/values-prod.yaml"
grep -Fq 'minAvailable: 1' "$traefik_dir/values-prod.yaml"
grep -Fq 'cpu: 100m' "$traefik_dir/values-prod.yaml"
grep -Fq 'memory: 128Mi' "$traefik_dir/values-prod.yaml"
grep -Fq 'cpu: 500m' "$traefik_dir/values-prod.yaml"
grep -Fq 'memory: 256Mi' "$traefik_dir/values-prod.yaml"

bash -n "$traefik_dir/install.sh"

echo 'Traefik configuration checks passed'
