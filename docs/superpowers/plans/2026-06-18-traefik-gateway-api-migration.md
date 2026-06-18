# Traefik Gateway API Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the retired ingress-nginx path with one pinned Traefik controller configuration and portable Gateway API routes that render from the same Helm templates for local Docker Desktop and production GKE.

**Architecture:** Install Traefik as cluster infrastructure from its official Helm chart, with shared controller values plus local and production overrides. Keep the application-owned `Gateway` and `HTTPRoute` in `k8s/hotel-booking`; local values render one HTTP listener, while production values render one HTTPS listener referencing an existing TLS Secret. Gateway API CRDs and `GatewayClass` remain infrastructure concerns, separate from the application release.

**Tech Stack:** Kubernetes Gateway API v1.5.1, Traefik Proxy Helm chart v41.0.0, Traefik Proxy v3.7.5, Helm 3, Kubernetes, Bash

---

## Scope and Decisions

- Replace `networking.k8s.io/v1 Ingress` with `gateway.networking.k8s.io/v1 Gateway` and `HTTPRoute`.
- Preserve the three prefix routes exactly:
  - `/reservations` -> `reservations:3004`
  - `/auth` -> `auth-http:3003`
  - `/users` -> `auth-http:3003`
- Use `GatewayClass` name `traefik` and controller name `traefik.io/gateway-controller`.
- Pin Gateway API CRDs to `v1.5.1` and the Traefik Helm chart to `41.0.0`.
- Disable Traefik's Kubernetes Ingress and Traefik CRD providers; enable only the Kubernetes Gateway provider.
- Keep the Traefik chart's default `Gateway` and `GatewayClass` disabled. This repository supplies one explicit `GatewayClass`, while the application chart owns its `Gateway`.
- Local: one Traefik replica, HTTP Gateway listener on Traefik's `web` entryPoint port 8000, host `hotel-booking.localhost`.
- Production: two Traefik replicas, resource requests/limits, PodDisruptionBudget, HTTPS Gateway listener on Traefik's `websecure` entryPoint port 8443, host and TLS Secret supplied during deployment.
- Do not add cert-manager, ExternalDNS, or automated ingress-nginx removal. Production certificate issuance and DNS ownership are external infrastructure concerns. The runbook verifies Traefik first, then gives an explicit ingress-nginx uninstall command.

## File Map

- Create: `k8s/tests/gateway-render.sh` - render-level regression test for local and production application routes.
- Delete: `k8s/hotel-booking/templates/ingress.yaml` - retired ingress-nginx routing object.
- Create: `k8s/hotel-booking/templates/gateway.yaml` - environment-driven HTTP or HTTPS application entry point.
- Create: `k8s/hotel-booking/templates/httproute.yaml` - shared host and three prefix routes.
- Modify: `k8s/hotel-booking/values.yaml` - replace `ingress` values with shared Gateway values.
- Create: `k8s/hotel-booking/values-local.yaml` - explicit local HTTP host/TLS overrides.
- Create: `k8s/hotel-booking/values-prod.yaml` - production HTTPS mode with deploy-time host and Secret requirements.
- Modify: `k8s/hotel-booking/Chart.yaml` - increment chart version for the routing API change.
- Create: `k8s/tests/traefik-config.sh` - static regression test for controller pins and environment policy.
- Create: `k8s/traefik/gateway-class.yaml` - cluster-scoped class binding Gateway API to Traefik.
- Create: `k8s/traefik/values-common.yaml` - shared single-provider Traefik configuration.
- Create: `k8s/traefik/values-local.yaml` - one-replica local controller settings.
- Create: `k8s/traefik/values-prod.yaml` - HA, PDB, and resource settings for production.
- Create: `k8s/traefik/install.sh` - pinned, environment-selecting CRD/controller installer.
- Create: `k8s/README.md` - local/prod deployment, verification, rollback, and ingress-nginx retirement runbook.

## External References

- Traefik Helm releases: https://github.com/traefik/traefik-helm-chart/releases/tag/v41.0.0
- Traefik Gateway provider: https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/
- Traefik Gateway routing: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/
- Gateway API v1.5.1: https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.5.1
- Gateway API HTTP routing: https://gateway-api.sigs.k8s.io/guides/http-routing/
- Gateway API TLS: https://gateway-api.sigs.k8s.io/guides/tls/

### Task 1: Add Failing Gateway Render Test

**Files:**

- Create: `k8s/tests/gateway-render.sh`
- Test: `k8s/hotel-booking/templates/ingress.yaml`
- Test: `k8s/hotel-booking/templates/gateway.yaml`
- Test: `k8s/hotel-booking/templates/httproute.yaml`
- Test: `k8s/hotel-booking/values-local.yaml`
- Test: `k8s/hotel-booking/values-prod.yaml`

- [ ] **Step 1: Create the render regression test**

Create `k8s/tests/gateway-render.sh`:

```bash
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
  --show-only templates/gateway.yaml > "$local_gateway"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-local \
  -f "$chart/values-local.yaml" \
  --show-only templates/httproute.yaml > "$local_route"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-prod \
  -f "$chart/values-prod.yaml" \
  --set-string gateway.host=booking.example.com \
  --set-string gateway.tls.certificateSecretName=hotel-booking-tls \
  --show-only templates/gateway.yaml > "$prod_gateway"

helm template hotel-booking "$chart" \
  --namespace hotel-booking-prod \
  -f "$chart/values-prod.yaml" \
  --set-string gateway.host=booking.example.com \
  --set-string gateway.tls.certificateSecretName=hotel-booking-tls \
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
if grep -Fq 'protocol: HTTP' "$prod_gateway"; then
  echo 'production Gateway unexpectedly exposes HTTP' >&2
  exit 1
fi

grep -Fq 'kind: HTTPRoute' "$prod_route"
grep -Fq 'sectionName: https' "$prod_route"
grep -Fq 'booking.example.com' "$prod_route"

rendered_all="$tmp_dir/all.yaml"
helm template hotel-booking "$chart" \
  --namespace hotel-booking-local \
  -f "$chart/values-local.yaml" > "$rendered_all"

if grep -Fq 'kind: Ingress' "$rendered_all"; then
  echo 'retired Ingress still renders' >&2
  exit 1
fi

echo 'Gateway render checks passed'
```

- [ ] **Step 2: Make the test executable**

Run:

```bash
rtk chmod +x k8s/tests/gateway-render.sh
```

Expected: command exits `0`.

- [ ] **Step 3: Run the test and verify the current chart fails**

Run:

```bash
rtk k8s/tests/gateway-render.sh
```

Expected: FAIL because `k8s/hotel-booking/values-local.yaml`, `templates/gateway.yaml`, and `templates/httproute.yaml` do not exist.

### Task 2: Replace Ingress with Gateway and HTTPRoute

**Files:**

- Delete: `k8s/hotel-booking/templates/ingress.yaml`
- Create: `k8s/hotel-booking/templates/gateway.yaml`
- Create: `k8s/hotel-booking/templates/httproute.yaml`
- Modify: `k8s/hotel-booking/values.yaml`
- Create: `k8s/hotel-booking/values-local.yaml`
- Create: `k8s/hotel-booking/values-prod.yaml`
- Modify: `k8s/hotel-booking/Chart.yaml`
- Test: `k8s/tests/gateway-render.sh`

- [ ] **Step 1: Replace ingress values with shared Gateway values**

In `k8s/hotel-booking/values.yaml`, replace:

```yaml
ingress:
  className: nginx
  host: hotel-booking.localhost
```

with:

```yaml
gateway:
  className: traefik
  host: hotel-booking.localhost
  tls:
    enabled: false
    certificateSecretName: ""
```

Keep the existing `images` block unchanged.

- [ ] **Step 2: Add explicit local route values**

Create `k8s/hotel-booking/values-local.yaml`:

```yaml
gateway:
  host: hotel-booking.localhost
  tls:
    enabled: false
    certificateSecretName: ""
```

- [ ] **Step 3: Add production route values**

Create `k8s/hotel-booking/values-prod.yaml`:

```yaml
gateway:
  host: ""
  tls:
    enabled: true
    certificateSecretName: ""
```

The empty strings are deliberate deployment inputs. The templates below reject a production render unless the deployment supplies both values.

- [ ] **Step 4: Create the application Gateway template**

Create `k8s/hotel-booking/templates/gateway.yaml`:

```yaml
{{- $host := required "gateway.host must be set" .Values.gateway.host -}}
{{- $listenerName := ternary "https" "http" .Values.gateway.tls.enabled -}}
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: hotel-booking
spec:
  gatewayClassName: {{ .Values.gateway.className | quote }}
  listeners:
    - name: {{ $listenerName }}
      hostname: {{ $host | quote }}
      protocol: {{ ternary "HTTPS" "HTTP" .Values.gateway.tls.enabled }}
      port: {{ ternary 8443 8000 .Values.gateway.tls.enabled }}
      allowedRoutes:
        namespaces:
          from: Same
      {{ if .Values.gateway.tls.enabled }}
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: {{ required "gateway.tls.certificateSecretName must be set when TLS is enabled" .Values.gateway.tls.certificateSecretName | quote }}
      {{ end }}
```

- [ ] **Step 5: Create the shared HTTPRoute template**

Create `k8s/hotel-booking/templates/httproute.yaml`:

```yaml
{{- $host := required "gateway.host must be set" .Values.gateway.host -}}
{{- $listenerName := ternary "https" "http" .Values.gateway.tls.enabled -}}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hotel-booking
spec:
  parentRefs:
    - name: hotel-booking
      sectionName: {{ $listenerName }}
  hostnames:
    - {{ $host | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /reservations
      backendRefs:
        - name: reservations
          port: 3004
    - matches:
        - path:
            type: PathPrefix
            value: /auth
      backendRefs:
        - name: auth-http
          port: 3003
    - matches:
        - path:
            type: PathPrefix
            value: /users
      backendRefs:
        - name: auth-http
          port: 3003
```

- [ ] **Step 6: Remove the retired Ingress template**

Delete:

```text
k8s/hotel-booking/templates/ingress.yaml
```

- [ ] **Step 7: Increment the application chart version**

In `k8s/hotel-booking/Chart.yaml`, change:

```yaml
version: 0.1.0
```

to:

```yaml
version: 0.2.0
```

Keep `appVersion` unchanged because this migration changes deployment manifests, not application code.

- [ ] **Step 8: Run the render regression test**

Run:

```bash
rtk k8s/tests/gateway-render.sh
```

Expected: PASS with:

```text
Gateway render checks passed
```

- [ ] **Step 9: Lint local values**

Run:

```bash
rtk helm lint k8s/hotel-booking -f k8s/hotel-booking/values-local.yaml
```

Expected: PASS with `1 chart(s) linted, 0 chart(s) failed`.

- [ ] **Step 10: Prove production inputs are mandatory**

Run:

```bash
rtk helm template hotel-booking k8s/hotel-booking \
  -f k8s/hotel-booking/values-prod.yaml
```

Expected: FAIL with `gateway.host must be set`.

- [ ] **Step 11: Lint production values with explicit deployment inputs**

Run:

```bash
rtk helm lint k8s/hotel-booking \
  -f k8s/hotel-booking/values-prod.yaml \
  --set-string gateway.host=booking.example.com \
  --set-string gateway.tls.certificateSecretName=hotel-booking-tls
```

Expected: PASS with `1 chart(s) linted, 0 chart(s) failed`.

- [ ] **Step 12: Commit application routing migration**

Run:

```bash
rtk git add \
  k8s/tests/gateway-render.sh \
  k8s/hotel-booking/Chart.yaml \
  k8s/hotel-booking/values.yaml \
  k8s/hotel-booking/values-local.yaml \
  k8s/hotel-booking/values-prod.yaml \
  k8s/hotel-booking/templates/gateway.yaml \
  k8s/hotel-booking/templates/httproute.yaml \
  k8s/hotel-booking/templates/ingress.yaml
rtk git commit -m "feat(k8s): migrate routes to Gateway API"
```

Expected: PASS. Commit contains only the route templates, route values, chart version, and render test.

### Task 3: Add Failing Traefik Infrastructure Test

**Files:**

- Create: `k8s/tests/traefik-config.sh`
- Test: `k8s/traefik/install.sh`
- Test: `k8s/traefik/gateway-class.yaml`
- Test: `k8s/traefik/values-common.yaml`
- Test: `k8s/traefik/values-local.yaml`
- Test: `k8s/traefik/values-prod.yaml`

- [ ] **Step 1: Create the controller configuration test**

Create `k8s/tests/traefik-config.sh`:

```bash
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
```

- [ ] **Step 2: Make the test executable**

Run:

```bash
rtk chmod +x k8s/tests/traefik-config.sh
```

Expected: command exits `0`.

- [ ] **Step 3: Run the test and verify it fails**

Run:

```bash
rtk k8s/tests/traefik-config.sh
```

Expected: FAIL because `k8s/traefik/install.sh` and the controller configuration files do not exist.

### Task 4: Add Pinned Traefik Controller Configuration

**Files:**

- Create: `k8s/traefik/gateway-class.yaml`
- Create: `k8s/traefik/values-common.yaml`
- Create: `k8s/traefik/values-local.yaml`
- Create: `k8s/traefik/values-prod.yaml`
- Create: `k8s/traefik/install.sh`
- Test: `k8s/tests/traefik-config.sh`

- [ ] **Step 1: Add the Traefik GatewayClass**

Create `k8s/traefik/gateway-class.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: traefik
spec:
  controllerName: traefik.io/gateway-controller
```

- [ ] **Step 2: Add shared controller values**

Create `k8s/traefik/values-common.yaml`:

```yaml
providers:
  kubernetesCRD:
    enabled: false
  kubernetesIngress:
    enabled: false
  kubernetesGateway:
    enabled: true

ingressClass:
  enabled: false

gateway:
  enabled: false

gatewayClass:
  enabled: false

service:
  type: LoadBalancer
```

- [ ] **Step 3: Add local controller values**

Create `k8s/traefik/values-local.yaml`:

```yaml
deployment:
  replicas: 1

podDisruptionBudget:
  enabled: false

resources: {}
```

- [ ] **Step 4: Add production controller values**

Create `k8s/traefik/values-prod.yaml`:

```yaml
deployment:
  replicas: 2

podDisruptionBudget:
  enabled: true
  minAvailable: 1

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

- [ ] **Step 5: Add the pinned installer**

Create `k8s/traefik/install.sh`:

```bash
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
```

- [ ] **Step 6: Make the installer executable**

Run:

```bash
rtk chmod +x k8s/traefik/install.sh
```

Expected: command exits `0`.

- [ ] **Step 7: Run controller configuration tests**

Run:

```bash
rtk k8s/tests/traefik-config.sh
```

Expected: PASS with:

```text
Traefik configuration checks passed
```

- [ ] **Step 8: Render the pinned Traefik chart locally**

Run:

```bash
rtk helm repo add traefik https://traefik.github.io/charts --force-update
rtk helm repo update traefik
rtk helm template traefik traefik/traefik \
  --version 41.0.0 \
  --namespace traefik \
  -f k8s/traefik/values-common.yaml \
  -f k8s/traefik/values-local.yaml > /tmp/traefik-local.yaml
```

Expected: PASS and `/tmp/traefik-local.yaml` contains the Traefik Deployment, Service, RBAC, and no chart-generated Gateway or GatewayClass.

- [ ] **Step 9: Verify provider and ownership boundaries in rendered controller YAML**

Run:

```bash
rtk rg -n -- \
  '--providers.kubernetesgateway=true|--providers.kubernetesingress=true|--providers.kubernetescrd=true|kind: Gateway$|kind: GatewayClass$' \
  /tmp/traefik-local.yaml
```

Expected: exactly one provider match, `--providers.kubernetesgateway=true`; no Kubernetes Ingress provider, Kubernetes CRD provider, Gateway, or GatewayClass match.

- [ ] **Step 10: Render production controller values**

Run:

```bash
rtk helm template traefik traefik/traefik \
  --version 41.0.0 \
  --namespace traefik \
  -f k8s/traefik/values-common.yaml \
  -f k8s/traefik/values-prod.yaml > /tmp/traefik-prod.yaml
rtk rg -n 'replicas: 2|minAvailable: 1|cpu: 100m|memory: 128Mi|cpu: 500m|memory: 256Mi' \
  /tmp/traefik-prod.yaml
```

Expected: PASS; rendered Deployment has two replicas and resource policy, and rendered PodDisruptionBudget has `minAvailable: 1`.

- [ ] **Step 11: Commit controller infrastructure**

Run:

```bash
rtk git add \
  k8s/tests/traefik-config.sh \
  k8s/traefik/gateway-class.yaml \
  k8s/traefik/values-common.yaml \
  k8s/traefik/values-local.yaml \
  k8s/traefik/values-prod.yaml \
  k8s/traefik/install.sh
rtk git commit -m "feat(k8s): add pinned Traefik controller"
```

Expected: PASS. Commit contains only Traefik infrastructure configuration and its static test.

### Task 5: Document Deployment, Verification, and Retirement

**Files:**

- Create: `k8s/README.md`

- [ ] **Step 1: Prove the runbook is absent**

Run:

```bash
rtk rg -n 'install.sh local|GatewayClass|hotel-booking-tls|helm uninstall ingress-nginx' k8s/README.md
```

Expected: FAIL because `k8s/README.md` does not exist.

- [ ] **Step 2: Create the Kubernetes runbook**

Create `k8s/README.md`:

````markdown
# Kubernetes deployment

This repository uses Traefik and Kubernetes Gateway API for external HTTP routing.

Pinned infrastructure:

- Gateway API CRDs: `v1.5.1`
- Traefik Helm chart: `41.0.0`
- GatewayClass: `traefik`

## Local Docker Desktop

Prerequisites: Docker Desktop Kubernetes enabled, current `kubectl` context set to Docker Desktop, Helm 3, and application Secrets already created in `hotel-booking-local`.

Install Gateway API and Traefik:

```bash
./k8s/traefik/install.sh local
```

Deploy the application using an existing image tag:

```bash
: "${IMAGE_TAG:?set IMAGE_TAG to a published application image tag}"
helm upgrade --install hotel-booking k8s/hotel-booking \
  --namespace hotel-booking-local \
  --create-namespace \
  -f k8s/hotel-booking/values-local.yaml \
  --set-string images.tag="$IMAGE_TAG"
```

Verify resource acceptance:

```bash
kubectl wait gatewayclass/traefik --for=condition=Accepted --timeout=120s
kubectl wait gateway/hotel-booking \
  --namespace hotel-booking-local \
  --for=condition=Programmed \
  --timeout=120s
kubectl get gateway,httproute --namespace hotel-booking-local
```

While ingress-nginx owns `localhost:80`, verify Traefik through a temporary port-forward and explicit Host headers:

```bash
kubectl port-forward service/traefik 18080:80 --namespace traefik &
TRAEFIK_PORT_FORWARD_PID=$!
trap 'kill "$TRAEFIK_PORT_FORWARD_PID" 2>/dev/null || true; wait "$TRAEFIK_PORT_FORWARD_PID" 2>/dev/null || true' EXIT
curl -i -H 'Host: hotel-booking.localhost' http://127.0.0.1:18080/users
curl -i -H 'Host: hotel-booking.localhost' http://127.0.0.1:18080/auth
curl -i -H 'Host: hotel-booking.localhost' http://127.0.0.1:18080/reservations
kill "$TRAEFIK_PORT_FORWARD_PID"
wait "$TRAEFIK_PORT_FORWARD_PID" 2>/dev/null || true
trap - EXIT
```

Expected application response: HTTP `401`. This proves the request reached the auth service; it is not a Traefik failure.

## Production GKE

Prerequisites:

- Current `kubectl` context points to the intended GKE cluster.
- DNS host resolves to the Traefik LoadBalancer address.
- A valid `kubernetes.io/tls` Secret exists in `hotel-booking-prod`.
- Application Secrets and Artifact Registry pull access exist in `hotel-booking-prod`.
- `HOTEL_BOOKING_HOST`, `HOTEL_BOOKING_TLS_SECRET`, and `SHORT_SHA` are set by the deployment environment.

Install the same controller with production capacity values:

```bash
./k8s/traefik/install.sh prod
```

Validate required deployment inputs:

```bash
: "${HOTEL_BOOKING_HOST:?set HOTEL_BOOKING_HOST}"
: "${HOTEL_BOOKING_TLS_SECRET:?set HOTEL_BOOKING_TLS_SECRET}"
: "${SHORT_SHA:?set SHORT_SHA}"
kubectl get secret "$HOTEL_BOOKING_TLS_SECRET" \
  --namespace hotel-booking-prod
```

Deploy the application:

```bash
helm upgrade --install hotel-booking k8s/hotel-booking \
  --namespace hotel-booking-prod \
  --create-namespace \
  -f k8s/hotel-booking/values-prod.yaml \
  --set-string gateway.host="$HOTEL_BOOKING_HOST" \
  --set-string gateway.tls.certificateSecretName="$HOTEL_BOOKING_TLS_SECRET" \
  --set-string images.tag="$SHORT_SHA"
```

Verify Gateway status and HTTPS routing:

```bash
kubectl wait gateway/hotel-booking \
  --namespace hotel-booking-prod \
  --for=condition=Programmed \
  --timeout=180s
kubectl describe gateway hotel-booking --namespace hotel-booking-prod
kubectl describe httproute hotel-booking --namespace hotel-booking-prod
curl -i "https://${HOTEL_BOOKING_HOST}/users"
```

Expected route response: HTTP `401`. This proves TLS termination and routing reached the authenticated application endpoint.

## Retire ingress-nginx

Do this only after all three Traefik routes work in the target cluster.

Inspect the installed release first:

```bash
helm list --all-namespaces | grep ingress-nginx
```

If the release is named `ingress-nginx` in namespace `ingress-nginx`, uninstall it:

```bash
helm uninstall ingress-nginx --namespace ingress-nginx
```

Do not delete the namespace until `kubectl get all --namespace ingress-nginx` confirms it contains no resources owned by another workload.

## Rollback

Select the target environment before inspecting or restoring releases:

```bash
ROLLBACK_ENV="${ROLLBACK_ENV:?set ROLLBACK_ENV to local or prod}"
case "$ROLLBACK_ENV" in
  local)
    APP_NAMESPACE=hotel-booking-local
    APP_VALUES=k8s/hotel-booking/values-local.yaml
    ;;
  prod)
    APP_NAMESPACE=hotel-booking-prod
    APP_VALUES=k8s/hotel-booking/values-prod.yaml
    ;;
  *)
    echo 'ROLLBACK_ENV must be local or prod' >&2
    return 64 2>/dev/null || exit 64
    ;;
esac
printf 'Target namespace: %s\nTarget values: %s\n' "$APP_NAMESPACE" "$APP_VALUES"
helm history hotel-booking --namespace "$APP_NAMESPACE"
```

If ingress-nginx has been retired and the selected application revision contains the old `Ingress`, restore ingress-nginx first using its original chart version and environment-specific values. Wait for its controller before restoring the application revision:

```bash
: "${INGRESS_NGINX_CHART_VERSION:?set the previously deployed ingress-nginx chart version}"
: "${INGRESS_NGINX_VALUES:?set the local or prod ingress-nginx values file}"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "$INGRESS_NGINX_CHART_VERSION" \
  --namespace ingress-nginx \
  --create-namespace \
  -f "$INGRESS_NGINX_VALUES"
kubectl rollout status deployment/ingress-nginx-controller \
  --namespace ingress-nginx \
  --timeout=180s
read -r -p "Application revision to restore: " PREVIOUS_REVISION
helm rollback hotel-booking "$PREVIOUS_REVISION" --namespace "$APP_NAMESPACE"
```

If ingress-nginx is still running, skip its restore and roll back the application directly. Enter only a revision shown by `helm history` for the selected namespace. Helm rollback reuses that revision's stored values; use `$APP_VALUES` for a fresh environment-specific deployment instead.

To roll back Traefik itself without changing application routing:

```bash
helm history traefik --namespace traefik
read -r -p "Traefik revision to restore: " TRAEFIK_PREVIOUS_REVISION
helm rollback traefik "$TRAEFIK_PREVIOUS_REVISION" --namespace traefik
```
````

- [ ] **Step 3: Verify the runbook covers both environments and safe retirement**

Run:

```bash
rtk rg -n \
  'install.sh local|install.sh prod|GatewayClass|HOTEL_BOOKING_HOST|HOTEL_BOOKING_TLS_SECRET|helm uninstall ingress-nginx|helm rollback' \
  k8s/README.md
```

Expected: PASS with matches for local install, production install, required TLS inputs, safe ingress-nginx retirement, and rollback.

- [ ] **Step 4: Commit the runbook**

Run:

```bash
rtk git add k8s/README.md
rtk git commit -m "docs(k8s): document Gateway API rollout"
```

Expected: PASS. Commit contains only `k8s/README.md`.

### Task 6: Run Final Static and Render Verification

**Files:**

- Test: `k8s/tests/gateway-render.sh`
- Test: `k8s/tests/traefik-config.sh`
- Test: `k8s/hotel-booking`
- Test: `k8s/traefik`
- Test: `k8s/README.md`

- [ ] **Step 1: Run both focused tests**

Run:

```bash
rtk k8s/tests/gateway-render.sh
rtk k8s/tests/traefik-config.sh
```

Expected: both PASS with:

```text
Gateway render checks passed
Traefik configuration checks passed
```

- [ ] **Step 2: Verify ingress-nginx references are gone from active manifests**

Run:

```bash
rtk rg -n 'kind: Ingress|ingressClassName:|className: nginx' k8s/hotel-booking
```

Expected: FAIL with no matches. The non-zero result is the success condition for this absence check.

- [ ] **Step 3: Verify all intended Gateway resources remain**

Run:

```bash
rtk rg -n 'kind: GatewayClass|kind: Gateway|kind: HTTPRoute|traefik.io/gateway-controller' k8s
```

Expected: PASS with GatewayClass in `k8s/traefik/gateway-class.yaml`, Gateway in `templates/gateway.yaml`, HTTPRoute in `templates/httproute.yaml`, and controller binding in the GatewayClass.

- [ ] **Step 4: Check whitespace and patch integrity**

Run:

```bash
rtk git diff --check
```

Expected: PASS with no output.

- [ ] **Step 5: Review only files in this migration**

Run:

```bash
rtk git status --short
rtk git log --oneline -3
```

Expected: three new commits for application routes, Traefik infrastructure, and runbook. Pre-existing modifications to service Deployments, image values, and untracked docs remain untouched unless they were deliberately included by the user before execution.

### Task 7: Validate on Local Docker Desktop Before Production

**Files:**

- Test: live Docker Desktop Kubernetes cluster

- [ ] **Step 1: Confirm the target cluster before mutating it**

Run:

```bash
rtk kubectl config current-context
rtk kubectl get nodes -o wide
```

Expected: current context is Docker Desktop's local Kubernetes context and all nodes report `Ready`. Stop if the context names a shared or production cluster.

- [ ] **Step 2: Install the local controller**

Run:

```bash
rtk ./k8s/traefik/install.sh local
```

Expected: Gateway API CRDs apply, Traefik rollout completes, and `gatewayclass/traefik` becomes `Accepted`.

- [ ] **Step 3: Deploy the application route manifests**

Run:

```bash
: "${IMAGE_TAG:?set IMAGE_TAG to a published application image tag}"
rtk helm upgrade --install hotel-booking k8s/hotel-booking \
  --namespace hotel-booking-local \
  --create-namespace \
  -f k8s/hotel-booking/values-local.yaml \
  --set-string images.tag="$IMAGE_TAG"
```

Expected: Helm upgrade succeeds. Existing application Secrets and image tag must already be valid for pods to become Ready.

- [ ] **Step 4: Verify Gateway API status**

Run:

```bash
rtk kubectl wait gateway/hotel-booking \
  --namespace hotel-booking-local \
  --for=condition=Programmed \
  --timeout=120s
rtk kubectl get gateway,httproute \
  --namespace hotel-booking-local \
  -o wide
```

Expected: Gateway is `Programmed=True`; HTTPRoute has accepted and resolved references.

- [ ] **Step 5: Verify all three routes**

Run:

```bash
rtk kubectl port-forward service/traefik 18080:80 --namespace traefik &
TRAEFIK_PORT_FORWARD_PID=$!
trap 'kill "$TRAEFIK_PORT_FORWARD_PID" 2>/dev/null || true; wait "$TRAEFIK_PORT_FORWARD_PID" 2>/dev/null || true' EXIT
rtk curl -i -H 'Host: hotel-booking.localhost' http://127.0.0.1:18080/users
rtk curl -i -H 'Host: hotel-booking.localhost' http://127.0.0.1:18080/auth
rtk curl -i -H 'Host: hotel-booking.localhost' http://127.0.0.1:18080/reservations
kill "$TRAEFIK_PORT_FORWARD_PID"
wait "$TRAEFIK_PORT_FORWARD_PID" 2>/dev/null || true
trap - EXIT
```

Expected: requests reach their NestJS services. Auth-protected routes may return `401`; no request returns a Traefik `404` or connection refusal.

- [ ] **Step 6: Record production gate**

Do not uninstall ingress-nginx or deploy production from this task. Production proceeds only after local status conditions and all three routes pass, a real DNS host is selected, and a valid TLS Secret exists in the production namespace.

## Self-Review Results

- Spec coverage: controller parity, Gateway API migration, three routes, local HTTP, production HTTPS, replica/PDB/resource differences, pinned versions, staged ingress-nginx retirement, and verification are each assigned to explicit tasks.
- Placeholder scan: no incomplete implementation steps. `booking.example.com` is an isolated render-test fixture; production deployment requires explicit environment variables. `PREVIOUS_REVISION` appears only as a documented argument that the operator replaces using `helm history` output.
- Type consistency: values use `gateway.className`, `gateway.host`, `gateway.tls.enabled`, and `gateway.tls.certificateSecretName` consistently across templates, tests, and runbook. Gateway listener names are `http` locally and `https` in production; HTTPRoute `sectionName` derives from the same TLS flag.
- Scope: cert issuance, DNS automation, application health probes, and unrelated service Deployment changes remain outside this migration.
