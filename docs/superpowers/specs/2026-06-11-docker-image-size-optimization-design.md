# Docker Image Size Optimization Design

## Goal

Reduce each production service image from the current 348-367 MB range to
250 MB or less without changing application behavior, the NestJS library
layout, Kubernetes resources, or the hardened runtime controls.

## Recommended Approach

Keep the existing four service Dockerfiles and webpack builds. Make each
application package own every non-built-in dependency required by its compiled
bundle, enable injected workspace packages, then use pnpm's filtered deploy
command to create a portable production dependency tree for that service.

This approach is preferred over converting `libs/common` into a workspace
package because the library is currently compiled into each application bundle.
Changing its package boundary would add unrelated architecture and build-system
risk. It is preferred over bundling all dependencies or moving to distroless
because those options have higher runtime compatibility and debugging risk.

## Dependency Ownership

Root `package.json` keeps repository tooling and shared development
dependencies. Runtime packages move to the `dependencies` section of every app
whose compiled `dist/apps/<service>/main.js` references them.

The implementation must derive the exact dependency matrix from fresh compiled
bundles rather than copying source-level imports blindly. Node built-ins are
excluded. Service-specific packages such as Stripe, Nodemailer, Passport, JWT,
and bcrypt remain owned only by the services that use them.

After the move:

- `pnpm install --frozen-lockfile` must still build all four applications.
- Each app manifest must independently describe its production runtime.
- Root runtime dependencies that no app needs directly must be removed.

## Dockerfile Flow

Each service Dockerfile retains its pinned Node 24 Alpine digest, BuildKit cache
mounts, non-root `node` user, and service-specific build command.

The production flow becomes:

1. Install the full workspace dependency graph in the build stage.
2. Build the selected NestJS application with webpack.
3. Run:

   ```sh
   pnpm --filter @hotel-booking/<service> --prod deploy /prod/<service>
   ```

4. Copy the deployed `node_modules` and package metadata into the runtime stage.
5. Copy only the selected compiled application output into the runtime stage.
6. Start the existing `dist/apps/<service>/main` entrypoint as UID 1000.

The workspace configuration enables `injectWorkspacePackages: true`, as required
by pnpm 11's modern deploy implementation. Modern deploy derives a dedicated
deployment lockfile from the shared workspace lockfile. `libs/common` remains
compiled into each webpack bundle rather than becoming a deployed workspace
package.

## Scope

Included:

- Root and per-app dependency ownership.
- `injectWorkspacePackages: true` workspace configuration.
- Lockfile updates.
- Production-stage Dockerfile changes for all four services.
- Existing `.dockerignore` preservation.
- Image-size and runtime verification.

Excluded:

- Converting `libs/common` into a workspace package.
- Replacing four Dockerfiles with one parameterized Dockerfile.
- Distroless or scratch runtime images.
- Changing webpack externalization.
- Cloud Build configuration and changed-service detection.
- Kubernetes or Helm changes.

Those excluded items can be evaluated independently after this change establishes
a measured production baseline.

## Failure Handling

- If a service fails at startup with `MODULE_NOT_FOUND`, add the missing direct
  runtime dependency to that app manifest and rerun the full verification.
- If `pnpm deploy` includes unrelated workspace packages, inspect the app
  dependency graph before adding Docker cleanup commands.
- If any image remains above 250 MB, record its layer breakdown. Do not switch
  base images or bundle dependencies within this change.
- If filtered deploy introduces behavior not reproduced by local installation,
  revert to the current production install flow and retain only proven
  dependency-ownership corrections.

## Verification

1. Run `pnpm install --frozen-lockfile`.
2. Build all four applications from a clean `dist`.
3. Extract non-built-in `require()` targets from each fresh compiled bundle and
   confirm each target exists in that app's production dependency graph.
4. Confirm `injectWorkspacePackages: true` is recorded in workspace configuration
   and the regenerated lockfile.
5. Run `pnpm --filter <service> --prod deploy` for all four services.
6. Build all four production Docker images without relying on stale image
   layers for the changed dependency/deploy steps.
7. Start each image with its required environment supplied far enough to prove
   module loading and NestJS bootstrap; expected external-service failures are
   acceptable only after bootstrap.
8. Confirm each runtime uses UID 1000 and contains no global pnpm executable.
9. Confirm each production image is 250 MB or less. Record exact before/after
   sizes.
10. Run `pnpm audit --prod` and ensure no new production advisory is introduced.
11. Run `git diff --check`.

## Success Criteria

- Four production images build successfully.
- Application startup behavior matches the current images.
- Each image remains pinned to the approved Node digest and runs non-root.
- No service depends on undeclared root production dependencies.
- Every image is 250 MB or less, or the change is paused for a documented size
  investigation rather than silently accepting a larger result.
