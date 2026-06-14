# syntax=docker/dockerfile:1

FROM node@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS development

WORKDIR /usr/src/app

COPY package.json ./
COPY pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./
COPY tsconfig.json tsconfig.json
COPY nest-cli.json nest-cli.json
COPY apps/notifications/package.json apps/notifications/package.json

RUN --mount=type=cache,id=pnpm-notifications,target=/pnpm/store \
    npm install -g pnpm@11.5.0 \
    && pnpm config set store-dir /pnpm/store \
    && pnpm install --frozen-lockfile

COPY apps/notifications apps/notifications
COPY libs libs

RUN pnpm run build notifications

FROM development AS deployment

RUN --mount=type=cache,id=pnpm-notifications,target=/pnpm/store \
    pnpm --filter @hotel-booking/notifications --prod deploy /prod/notifications

FROM node@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS production

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

WORKDIR /usr/src/app

COPY --chown=node:node --from=deployment /prod/notifications/package.json ./package.json
COPY --chown=node:node --from=deployment /prod/notifications/node_modules ./node_modules
COPY --chown=node:node --from=development /usr/src/app/dist/apps/notifications ./dist/apps/notifications

USER node

CMD ["node", "dist/apps/notifications/main"]
