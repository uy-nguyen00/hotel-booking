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

While ingress-nginx is still installed, `localhost:80` reaches ingress-nginx rather than Traefik. Temporarily forward local port `18080` to Traefik's HTTP Service port, then send the expected Host header for each route:

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

Expected: requests reach their application services. Auth-protected routes may return HTTP `401`; none should return a Traefik `404` or connection refusal.

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
