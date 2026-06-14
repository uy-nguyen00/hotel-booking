# syntax=docker/dockerfile:1

FROM node@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS development

WORKDIR /usr/src/app

COPY package.json ./
COPY pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./
COPY tsconfig.json tsconfig.json
COPY nest-cli.json nest-cli.json
COPY apps/auth/package.json apps/auth/package.json

RUN --mount=type=cache,id=pnpm-auth,target=/pnpm/store \
    npm install -g pnpm@11.5.0 \
    && pnpm config set store-dir /pnpm/store \
    && pnpm install --frozen-lockfile

COPY apps/auth apps/auth
COPY libs libs

RUN pnpm run build auth

FROM development AS deployment

RUN --mount=type=cache,id=pnpm-auth,target=/pnpm/store \
    pnpm --filter @hotel-booking/auth --prod deploy /prod/auth

FROM node@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS production

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

WORKDIR /usr/src/app

COPY --chown=node:node --from=deployment /prod/auth/package.json ./package.json
COPY --chown=node:node --from=deployment /prod/auth/node_modules ./node_modules
COPY --chown=node:node --from=development /usr/src/app/dist/apps/auth ./dist/apps/auth

USER node

CMD ["node", "dist/apps/auth/main"]
