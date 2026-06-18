# Cloud Build Image Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-service local Docker push note with a reproducible Cloud Build pipeline that builds and pushes all four production images, then lets Helm deploy an exact commit-tagged image set.

**Architecture:** Keep the existing service-specific production Dockerfiles and add one root `cloudbuild.yaml` that builds each service with `--target production`. Store the four images in one Artifact Registry Docker repository named `hotel-booking`, tagged by Cloud Build's `$SHORT_SHA`, and make the Helm chart read image registry/tag values instead of hardcoding old image URLs.

**Tech Stack:** Google Cloud Build, Artifact Registry, Docker BuildKit, Helm, Kubernetes, Node.js 24 Alpine, pnpm 11.5.0

---

## Current State

- `docker-img-push.txt` builds and pushes only `apps/reservations/Dockerfile`.
- `docker-img-push.txt` uses implicit Docker tag `latest` through `.../reservations/production`.
- `k8s/hotel-booking/templates/*/deployment.yaml` hardcodes `europe-west9-docker.pkg.dev/hotel-booking-dev-498209/<service>/production`.
- The desired project and region from the current push note are `hotel-booking-dev-499018` and `europe-west1`.
- No `cloudbuild.yaml` exists.

## File Map

- Create: `cloudbuild.yaml` - Cloud Build config that builds and publishes `reservations`, `auth`, `payments`, and `notifications`.
- Modify: `k8s/hotel-booking/values.yaml` - shared image registry, tag, and pull policy.
- Modify: `k8s/hotel-booking/templates/reservations/deployment.yaml` - configurable reservations image.
- Modify: `k8s/hotel-booking/templates/auth/deployment.yaml` - configurable auth image.
- Modify: `k8s/hotel-booking/templates/payments/deployment.yaml` - configurable payments image.
- Modify: `k8s/hotel-booking/templates/notifications/deployment.yaml` - configurable notifications image.
- Modify: `docker-img-push.txt` - replace stale local one-service push commands with the manual Cloud Build submit command.

## External References

- Cloud Build Docker image builds: https://docs.cloud.google.com/build/docs/building/build-containers
- Cloud Build substitutions: https://docs.cloud.google.com/build/docs/configuring-builds/substitute-variable-values
- Cloud Build triggers: https://docs.cloud.google.com/build/docs/automating-builds/create-manage-triggers
- Cloud Build user-specified service accounts: https://docs.cloud.google.com/build/docs/securing-builds/configure-user-specified-service-accounts

## Task 1: Prove Current Image Pipeline Gaps

**Files:**

- Test: `cloudbuild.yaml`
- Test: `docker-img-push.txt`
- Test: `k8s/hotel-booking/templates/reservations/deployment.yaml`
- Test: `k8s/hotel-booking/templates/auth/deployment.yaml`
- Test: `k8s/hotel-booking/templates/payments/deployment.yaml`
- Test: `k8s/hotel-booking/templates/notifications/deployment.yaml`

- [ ] **Step 1: Prove Cloud Build config is missing**

Run:

```bash
rtk test -f cloudbuild.yaml
```

Expected: FAIL with non-zero exit code because `cloudbuild.yaml` does not exist.

- [ ] **Step 2: Prove manual push file only covers reservations**

Run:

```bash
rtk rg -n "apps/(auth|payments|notifications)/Dockerfile|cloudbuild.yaml|gcloud builds submit" docker-img-push.txt
```

Expected: FAIL with no matches. The file has no Cloud Build submit command and no build lines for the other three services.

- [ ] **Step 3: Prove Helm image refs are hardcoded**

Run:

```bash
rtk rg -n "europe-west9-docker.pkg.dev/hotel-booking-dev-498209/.*/production" k8s/hotel-booking/templates
```

Expected: PASS with four matches, one per service deployment.

- [ ] **Step 4: Prove Helm values do not control image refs**

Run:

```bash
rtk rg -n "images:|registry:|tag:|pullPolicy:" k8s/hotel-booking/values.yaml
```

Expected: FAIL with no matches.

## Task 2: Add Cloud Build Image Builder

**Files:**

- Create: `cloudbuild.yaml`

- [ ] **Step 1: Create `cloudbuild.yaml`**

Create `cloudbuild.yaml`:

```yaml
substitutions:
  _LOCATION: europe-west1
  _REPOSITORY: hotel-booking

options:
  logging: CLOUD_LOGGING_ONLY

timeout: 1800s

steps:
  - id: build-reservations
    name: gcr.io/cloud-builders/docker
    env:
      - DOCKER_BUILDKIT=1
    args:
      - build
      - --target
      - production
      - -f
      - apps/reservations/Dockerfile
      - -t
      - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/reservations:$SHORT_SHA
      - .

  - id: build-auth
    name: gcr.io/cloud-builders/docker
    env:
      - DOCKER_BUILDKIT=1
    args:
      - build
      - --target
      - production
      - -f
      - apps/auth/Dockerfile
      - -t
      - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/auth:$SHORT_SHA
      - .

  - id: build-payments
    name: gcr.io/cloud-builders/docker
    env:
      - DOCKER_BUILDKIT=1
    args:
      - build
      - --target
      - production
      - -f
      - apps/payments/Dockerfile
      - -t
      - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/payments:$SHORT_SHA
      - .

  - id: build-notifications
    name: gcr.io/cloud-builders/docker
    env:
      - DOCKER_BUILDKIT=1
    args:
      - build
      - --target
      - production
      - -f
      - apps/notifications/Dockerfile
      - -t
      - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/notifications:$SHORT_SHA
      - .

images:
  - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/reservations:$SHORT_SHA
  - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/auth:$SHORT_SHA
  - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/payments:$SHORT_SHA
  - ${_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/notifications:$SHORT_SHA
```

- [ ] **Step 2: Validate Cloud Build config has all services**

Run:

```bash
rtk rg -n "id: build-(reservations|auth|payments|notifications)" cloudbuild.yaml
```

Expected: PASS with four matches:

```text
build-reservations
build-auth
build-payments
build-notifications
```

- [ ] **Step 3: Validate images use commit tag**

Run:

```bash
rtk rg -n "\\$SHORT_SHA" cloudbuild.yaml
```

Expected: PASS with eight matches: four build tags and four `images` entries.

- [ ] **Step 4: Validate build target is production for every service**

Run:

```bash
rtk rg -n -- "--target" cloudbuild.yaml
```

Expected: PASS with four matches.

- [ ] **Step 5: Commit Cloud Build config**

Run:

```bash
rtk git add cloudbuild.yaml
rtk git commit -m "feat(build): add cloud build image pipeline"
```

Expected: PASS. Commit contains only `cloudbuild.yaml`.

## Task 3: Make Helm Images Value-Driven

**Files:**

- Modify: `k8s/hotel-booking/values.yaml`
- Modify: `k8s/hotel-booking/templates/reservations/deployment.yaml`
- Modify: `k8s/hotel-booking/templates/auth/deployment.yaml`
- Modify: `k8s/hotel-booking/templates/payments/deployment.yaml`
- Modify: `k8s/hotel-booking/templates/notifications/deployment.yaml`

- [ ] **Step 1: Add shared image values**

Replace `k8s/hotel-booking/values.yaml` with:

```yaml
ingress:
  className: nginx
  host: hotel-booking.localhost

images:
  registry: europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking
  tag: dev
  pullPolicy: IfNotPresent
```

- [ ] **Step 2: Update reservations image**

In `k8s/hotel-booking/templates/reservations/deployment.yaml`, replace:

```yaml
        - image: europe-west9-docker.pkg.dev/hotel-booking-dev-498209/reservations/production
          name: reservations
```

with:

```yaml
        - image: "{{ .Values.images.registry }}/reservations:{{ .Values.images.tag }}"
          imagePullPolicy: {{ .Values.images.pullPolicy | quote }}
          name: reservations
```

- [ ] **Step 3: Update auth image**

In `k8s/hotel-booking/templates/auth/deployment.yaml`, replace:

```yaml
        - image: europe-west9-docker.pkg.dev/hotel-booking-dev-498209/auth/production
          name: auth
```

with:

```yaml
        - image: "{{ .Values.images.registry }}/auth:{{ .Values.images.tag }}"
          imagePullPolicy: {{ .Values.images.pullPolicy | quote }}
          name: auth
```

- [ ] **Step 4: Update payments image**

In `k8s/hotel-booking/templates/payments/deployment.yaml`, replace:

```yaml
        - image: europe-west9-docker.pkg.dev/hotel-booking-dev-498209/payments/production
          name: payments
```

with:

```yaml
        - image: "{{ .Values.images.registry }}/payments:{{ .Values.images.tag }}"
          imagePullPolicy: {{ .Values.images.pullPolicy | quote }}
          name: payments
```

- [ ] **Step 5: Update notifications image**

In `k8s/hotel-booking/templates/notifications/deployment.yaml`, replace:

```yaml
        - image: europe-west9-docker.pkg.dev/hotel-booking-dev-498209/notifications/production
          name: notifications
```

with:

```yaml
        - image: "{{ .Values.images.registry }}/notifications:{{ .Values.images.tag }}"
          imagePullPolicy: {{ .Values.images.pullPolicy | quote }}
          name: notifications
```

- [ ] **Step 6: Render Helm chart with Cloud Build tag**

Run:

```bash
rtk helm template hotel-booking k8s/hotel-booking --set images.tag=test-sha
```

Expected: PASS. Output includes these four image refs:

```text
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/reservations:test-sha
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/auth:test-sha
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/payments:test-sha
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/notifications:test-sha
```

- [ ] **Step 7: Lint Helm chart**

Run:

```bash
rtk helm lint k8s/hotel-booking --set images.tag=test-sha
```

Expected: PASS with:

```text
1 chart(s) linted, 0 chart(s) failed
```

- [ ] **Step 8: Confirm old hardcoded registry is gone**

Run:

```bash
rtk rg -n "europe-west9-docker.pkg.dev|hotel-booking-dev-498209|/production" k8s/hotel-booking
```

Expected: FAIL with no matches.

- [ ] **Step 9: Commit Helm image values**

Run:

```bash
rtk git add k8s/hotel-booking/values.yaml k8s/hotel-booking/templates/reservations/deployment.yaml k8s/hotel-booking/templates/auth/deployment.yaml k8s/hotel-booking/templates/payments/deployment.yaml k8s/hotel-booking/templates/notifications/deployment.yaml
rtk git commit -m "feat(k8s): make service images configurable"
```

Expected: PASS. Commit contains only Helm chart image reference changes.

## Task 4: Update Manual Push Note

**Files:**

- Modify: `docker-img-push.txt`

- [ ] **Step 1: Replace local one-service Docker push commands**

Replace `docker-img-push.txt` with:

```text
# Preferred path: Cloud Build builds and pushes all service images from cloudbuild.yaml.
# Use this manual submit command to test the same pipeline without waiting for a trigger.

COMMIT_SHA=$(git rev-parse HEAD)
SHORT_SHA=$(git rev-parse --short=7 HEAD)

gcloud builds submit \
  --project=hotel-booking-dev-499018 \
  --config=cloudbuild.yaml \
  --substitutions=COMMIT_SHA="$COMMIT_SHA",SHORT_SHA="$SHORT_SHA" \
  .

# Deploy the same image tag with Helm:
helm upgrade --install hotel-booking k8s/hotel-booking \
  --namespace hotel-booking-local \
  --create-namespace \
  --set images.tag="$SHORT_SHA"
```

- [ ] **Step 2: Verify old one-service local push is gone**

Run:

```bash
rtk rg -n "docker build -t reservations|docker tag reservations|docker image push europe-west1-docker.pkg.dev/hotel-booking-dev-499018/reservations/production" docker-img-push.txt
```

Expected: FAIL with no matches.

- [ ] **Step 3: Verify note points to Cloud Build**

Run:

```bash
rtk rg -n "gcloud builds submit|cloudbuild.yaml|helm upgrade --install" docker-img-push.txt
```

Expected: PASS with three matches.

- [ ] **Step 4: Commit manual note update**

Run:

```bash
rtk git add docker-img-push.txt
rtk git commit -m "docs(build): document cloud build image submit"
```

Expected: PASS. Commit contains only `docker-img-push.txt`.

## Task 5: Set Up Google Cloud Resources

**Files:**

- External: Google Cloud project `hotel-booking-dev-499018`
- External: Artifact Registry repository `hotel-booking`
- External: Cloud Build trigger

- [ ] **Step 1: Set project and enable APIs**

Run:

```bash
rtk gcloud config set project hotel-booking-dev-499018
rtk gcloud services enable cloudbuild.googleapis.com artifactregistry.googleapis.com iam.googleapis.com
```

Expected: PASS. Enabled services include Cloud Build, Artifact Registry, and IAM.

- [ ] **Step 2: Create Artifact Registry repository**

Run:

```bash
rtk gcloud artifacts repositories describe hotel-booking --location=europe-west1
```

Expected when repository already exists: PASS with repository metadata.

When command returns `NOT_FOUND`, run:

```bash
rtk gcloud artifacts repositories create hotel-booking \
  --repository-format=docker \
  --location=europe-west1 \
  --description="Hotel Booking service images"
```

Expected: PASS. Repository `europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking` exists.

- [ ] **Step 3: Create least-privilege Cloud Build service account**

Run:

```bash
rtk gcloud iam service-accounts create cloud-build-hotel-booking \
  --display-name="Cloud Build Hotel Booking"
```

Expected when service account is new: PASS.

Expected when service account already exists: FAIL with `already exists`; continue to Step 4 because the target service account exists.

- [ ] **Step 4: Grant push permission to Artifact Registry**

Run:

```bash
rtk gcloud artifacts repositories add-iam-policy-binding hotel-booking \
  --location=europe-west1 \
  --member=serviceAccount:cloud-build-hotel-booking@hotel-booking-dev-499018.iam.gserviceaccount.com \
  --role=roles/artifactregistry.writer
```

Expected: PASS. IAM policy includes `roles/artifactregistry.writer` for the Cloud Build service account.

- [ ] **Step 5: Grant build log permission**

Run:

```bash
rtk gcloud projects add-iam-policy-binding hotel-booking-dev-499018 \
  --member=serviceAccount:cloud-build-hotel-booking@hotel-booking-dev-499018.iam.gserviceaccount.com \
  --role=roles/logging.logWriter
```

Expected: PASS. User-specified Cloud Build service account can write logs to Cloud Logging.

- [ ] **Step 6: Create Cloud Build trigger in console**

Open Cloud Build Triggers for project `hotel-booking-dev-499018` and create a trigger with these exact settings:

```text
Name: hotel-booking-image-build-main
Region: europe-west1
Event: Push to a branch
Branch: ^main$
Configuration type: Cloud Build configuration file
Location: Repository
Cloud Build configuration file location: cloudbuild.yaml
Service account: cloud-build-hotel-booking@hotel-booking-dev-499018.iam.gserviceaccount.com
Included files:
  apps/**
  libs/**
  package.json
  pnpm-lock.yaml
  pnpm-workspace.yaml
  nest-cli.json
  tsconfig.json
  tsconfig.build.json
  cloudbuild.yaml
  k8s/hotel-booking/**
Ignored files:
  docs/**
  README.md
  docker-img-push.txt
```

Expected: Trigger exists and runs only when source/build/deploy files change on `main`.

## Task 6: Verify Manual Cloud Build Submit

**Files:**

- Test: `cloudbuild.yaml`
- Test: Artifact Registry repository `hotel-booking`

- [ ] **Step 1: Run manual Cloud Build submit**

Run:

```bash
COMMIT_SHA=$(git rev-parse HEAD)
SHORT_SHA=$(git rev-parse --short=7 HEAD)
rtk gcloud builds submit --project=hotel-booking-dev-499018 --config=cloudbuild.yaml --substitutions=COMMIT_SHA="$COMMIT_SHA",SHORT_SHA="$SHORT_SHA" .
```

Expected: PASS. Build produces and pushes four images:

```text
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/reservations:$SHORT_SHA
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/auth:$SHORT_SHA
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/payments:$SHORT_SHA
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/notifications:$SHORT_SHA
```

- [ ] **Step 2: Verify Artifact Registry tags**

Run:

```bash
rtk gcloud artifacts docker tags list europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/reservations
rtk gcloud artifacts docker tags list europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/auth
rtk gcloud artifacts docker tags list europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/payments
rtk gcloud artifacts docker tags list europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/notifications
```

Expected: PASS. Each command shows the current `$SHORT_SHA` tag.

- [ ] **Step 3: Verify Helm deploy command renders pushed tag**

Run:

```bash
SHORT_SHA=$(git rev-parse --short=7 HEAD)
rtk helm template hotel-booking k8s/hotel-booking --set images.tag="$SHORT_SHA"
```

Expected: PASS. Rendered manifests reference the same `$SHORT_SHA` used by Cloud Build.

## Task 7: Verify Trigger Build

**Files:**

- External: Cloud Build trigger `hotel-booking-image-build-main`

- [ ] **Step 1: Run trigger manually from Cloud Console**

Open trigger `hotel-booking-image-build-main` and click `Run`.

Expected: Cloud Build starts from the current `main` branch commit and reaches `SUCCESS`.

- [ ] **Step 2: Verify trigger build substitutions**

Open the successful build details.

Expected: Build substitution values include:

```text
PROJECT_ID=hotel-booking-dev-499018
SHORT_SHA=<first seven characters of the main branch commit>
COMMIT_SHA=<full main branch commit>
```

- [ ] **Step 3: Verify image result visibility**

Open the successful build details and check build artifacts.

Expected: Build results list these four images:

```text
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/reservations:<trigger SHORT_SHA>
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/auth:<trigger SHORT_SHA>
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/payments:<trigger SHORT_SHA>
europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/notifications:<trigger SHORT_SHA>
```

## Task 8: Final Local Verification

**Files:**

- Test: `cloudbuild.yaml`
- Test: `docker-img-push.txt`
- Test: `k8s/hotel-booking`

- [ ] **Step 1: Run whitespace check**

Run:

```bash
rtk git diff --check
```

Expected: PASS with no output.

- [ ] **Step 2: Run Helm lint**

Run:

```bash
rtk helm lint k8s/hotel-booking --set images.tag=test-sha
```

Expected: PASS with:

```text
1 chart(s) linted, 0 chart(s) failed
```

- [ ] **Step 3: Check final diff**

Run:

```bash
rtk git status --short
rtk git diff --stat
```

Expected: Working tree contains only intentional changes during implementation. After commits, no staged or unstaged changes remain.

## Rollback Plan

- Revert `cloudbuild.yaml` to stop repo-defined Cloud Build image builds.
- Disable trigger `hotel-booking-image-build-main` in Cloud Build Triggers.
- Revert Helm image template changes to restore previous hardcoded image refs.
- Existing images in Artifact Registry remain inert until referenced by Helm.

## Success Criteria

- `cloudbuild.yaml` builds all four production Dockerfiles.
- Cloud Build pushes all four images under `europe-west1-docker.pkg.dev/hotel-booking-dev-499018/hotel-booking/<service>:$SHORT_SHA`.
- Helm renders image refs from `images.registry` and `images.tag`.
- No Kubernetes deployment template contains old `europe-west9` or `hotel-booking-dev-498209` image refs.
- Trigger `hotel-booking-image-build-main` can build from `main` without local Docker commands.
- `docker-img-push.txt` no longer suggests local one-service `latest` push as the primary workflow.
