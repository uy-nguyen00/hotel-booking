#To run this: docker build ../../ -f Dockerfile -t hb_reservations

FROM node:24-alpine AS development

WORKDIR /usr/src/app

COPY package.json ./
COPY pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./
COPY tsconfig.json tsconfig.json
COPY nest-cli.json nest-cli.json
COPY apps/payments/package.json apps/payments/package.json

RUN npm install -g pnpm@11.5.0 \
    && pnpm install --frozen-lockfile

COPY apps/payments apps/payments
COPY libs libs

RUN pnpm run build payments

FROM node:24-alpine AS production

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

WORKDIR /usr/src/app

COPY package.json ./
COPY pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./
COPY apps/payments/package.json apps/payments/package.json

RUN npm install -g pnpm@11.5.0 \
    && pnpm install --prod --frozen-lockfile

COPY --from=development /usr/src/app/dist ./dist

CMD ["node", "dist/apps/payments/main"]
