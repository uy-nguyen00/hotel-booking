# syntax=docker/dockerfile:1

FROM node@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS development

WORKDIR /usr/src/app

COPY package.json ./
COPY pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./
COPY tsconfig.json tsconfig.json
COPY nest-cli.json nest-cli.json
COPY apps/reservations/package.json apps/reservations/package.json

RUN --mount=type=cache,id=pnpm-reservations,target=/pnpm/store \
    npm install -g pnpm@11.5.0 \
    && pnpm config set store-dir /pnpm/store \
    && pnpm install --frozen-lockfile

COPY apps/reservations apps/reservations
COPY libs libs

RUN pnpm run build reservations

FROM development AS deployment

RUN --mount=type=cache,id=pnpm-reservations,target=/pnpm/store \
    pnpm --filter @hotel-booking/reservations --prod deploy /prod/reservations

FROM node@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS production

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

WORKDIR /usr/src/app

COPY --chown=node:node --from=deployment /prod/reservations/package.json ./package.json
COPY --chown=node:node --from=deployment /prod/reservations/node_modules ./node_modules
COPY --chown=node:node --from=development /usr/src/app/dist/apps/reservations ./dist/apps/reservations

USER node

CMD ["node", "dist/apps/reservations/main"]
