# GKE Managed Ingress with sslip.io

Use this runbook to expose `hotel-booking` on GKE with Google Cloud HTTP(S) Load
Balancing, Google ManagedCertificate, and a free sslip.io hostname.

## Assumptions

- Google Cloud project: `hotel-booking-dev-499018`
- Reserved global IP name: `hotel-booking-ip`
- ManagedCertificate name: `hotel-booking-cert`
- Helm release: `hotel-booking`
- Chart path: `k8s/hotel-booking`
- Namespace: `hotel-booking`
- Image tag: seven-character Git SHA from the checked-out revision

Set deployment variables:

```bash
GKE_NAMESPACE="hotel-booking"
IMAGE_TAG="$(rtk git rev-parse --short=7 HEAD)"
```

## Reserve or Reuse Global Static IP

Create the IP once:

```bash
rtk gcloud compute addresses create hotel-booking-ip \
  --global \
  --project=hotel-booking-dev-499018
```

If it already exists, keep using it.

Read the allocated address and derive the sslip.io hostname:

```bash
GKE_IP="$(rtk gcloud compute addresses describe hotel-booking-ip \
  --global \
  --project=hotel-booking-dev-499018 \
  --format='value(address)')"

GKE_HOST="hotel-booking.${GKE_IP}.sslip.io"

printf '%s\n' "$GKE_HOST"
```

Expected hostname shape:

```text
hotel-booking.34.120.10.20.sslip.io
```

## Verify Artifact Registry Pull Access

The GKE node pool service account needs Artifact Registry read access. Do not
create or patch `gcr-json-key` for GKE image pulls.

```bash
PROJECT_NUMBER="$(rtk gcloud projects describe hotel-booking-dev-499018 \
  --format='value(projectNumber)')"

NODE_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

rtk gcloud artifacts repositories add-iam-policy-binding production \
  --location=europe-west1 \
  --project=hotel-booking-dev-499018 \
  --member="serviceAccount:${NODE_SA_EMAIL}" \
  --role="roles/artifactregistry.reader"
```

This assumes the node pool uses the default Compute Engine service account. If
the node pool uses a custom service account, set `NODE_SA_EMAIL` to that service
account email before running the policy binding command.

## Deploy

```bash
rtk kubectl create namespace "$GKE_NAMESPACE"

rtk helm upgrade --install hotel-booking \
  k8s/hotel-booking \
  --namespace "$GKE_NAMESPACE" \
  -f k8s/hotel-booking/values-gke.yaml \
  --set images.tag="$IMAGE_TAG" \
  --set-string ingress.host="$GKE_HOST" \
  --set-string ingress.managedCertificate.domains[0]="$GKE_HOST" \
  --wait \
  --timeout 10m
```

If the namespace already exists, `kubectl create namespace` prints an AlreadyExists
error; continue with the Helm command.

## Verify

```bash
rtk kubectl get ingress,managedcertificate -n "$GKE_NAMESPACE"
rtk kubectl describe ingress hotel-booking -n "$GKE_NAMESPACE"
rtk kubectl describe managedcertificate hotel-booking-cert -n "$GKE_NAMESPACE"
```

Certificate provisioning can take several minutes after the load balancer IP and
sslip.io DNS resolve correctly.

Check HTTPS after the certificate becomes active:

```bash
rtk curl -si "https://${GKE_HOST}/health"
```

Expected response includes:

```http
HTTP/2 200
```

or:

```http
HTTP/1.1 200 OK
```
