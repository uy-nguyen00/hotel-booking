#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chart="$repo_root/k8s/hotel-booking"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

local_gateway="$tmp_dir/local-gateway.yaml"
local_route="$tmp_dir/local-route.yaml"
prod_gateway="$tmp_dir/prod-gateway.yaml"
prod_route="$tmp_dir/prod-route.yaml"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-local \
  -f "$chart/values-local.yaml" \
  --set-string images.tag=test \
  --show-only templates/gateway.yaml > "$local_gateway"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-local \
  -f "$chart/values-local.yaml" \
  --set-string images.tag=test \
  --show-only templates/httproute.yaml > "$local_route"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-prod \
  -f "$chart/values-prod.yaml" \
  --set-string gateway.host=booking.example.com \
  --set-string gateway.tls.certificateSecretName=hotel-booking-tls \
  --set-string images.tag=test \
  --show-only templates/gateway.yaml > "$prod_gateway"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-prod \
  -f "$chart/values-prod.yaml" \
  --set-string gateway.host=booking.example.com \
  --set-string gateway.tls.certificateSecretName=hotel-booking-tls \
  --set-string images.tag=test \
  --show-only templates/httproute.yaml > "$prod_route"

grep -Fq 'kind: Gateway' "$local_gateway"
grep -Fq 'gatewayClassName: "traefik"' "$local_gateway"
grep -Fq 'hostname: "hotel-booking.localhost"' "$local_gateway"
grep -Fq 'name: http' "$local_gateway"
grep -Fq 'protocol: HTTP' "$local_gateway"
grep -Fq 'port: 8000' "$local_gateway"
if grep -Fq 'certificateRefs:' "$local_gateway"; then
  echo 'local Gateway unexpectedly contains TLS certificateRefs' >&2
  exit 1
fi

grep -Fq 'kind: HTTPRoute' "$local_route"
grep -Fq 'sectionName: http' "$local_route"
grep -Fq 'hotel-booking.localhost' "$local_route"
grep -Fq 'value: "/reservations"' "$local_route"
grep -Fq 'value: "/auth"' "$local_route"
grep -Fq 'value: "/users"' "$local_route"
grep -Fq 'name: reservations' "$local_route"
grep -Fq 'port: 3004' "$local_route"
test "$(grep -Fc 'name: auth-http' "$local_route")" -eq 2
test "$(grep -Fc 'port: 3003' "$local_route")" -eq 2

grep -Fq 'kind: Gateway' "$prod_gateway"
grep -Fq 'hostname: "booking.example.com"' "$prod_gateway"
grep -Fq 'name: https' "$prod_gateway"
grep -Fq 'protocol: HTTPS' "$prod_gateway"
grep -Fq 'port: 8443' "$prod_gateway"
grep -Fq 'mode: Terminate' "$prod_gateway"
grep -Fq 'name: "hotel-booking-tls"' "$prod_gateway"
if grep -Eq '^[[:space:]]*protocol: HTTP$' "$prod_gateway"; then
  echo 'production Gateway unexpectedly exposes HTTP' >&2
  exit 1
fi

grep -Fq 'kind: HTTPRoute' "$prod_route"
grep -Fq 'sectionName: https' "$prod_route"
grep -Fq 'booking.example.com' "$prod_route"

rendered_all="$tmp_dir/all.yaml"
helm template hotel-booking "$chart" \
  --namespace hotel-booking-local \
  -f "$chart/values-local.yaml" \
  --set-string images.tag=test > "$rendered_all"

if grep -Fq 'kind: Ingress' "$rendered_all"; then
  echo 'retired Ingress still renders' >&2
  exit 1
fi

echo 'Gateway render checks passed'
