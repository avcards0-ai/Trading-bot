# syntax=docker/dockerfile:1
# Behind a TLS-intercepting proxy, pass its CA without baking it into a layer:
#   docker build --secret id=npm_ca,src=/path/to/ca.pem ...
# Build context: repository root (docker build -f apps/frontend/Dockerfile .)

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/backend/package.json apps/backend/
COPY apps/frontend/package.json apps/frontend/
RUN --mount=type=secret,id=npm_ca,required=false \
    if [ -f /run/secrets/npm_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/npm_ca; fi; \
    npm ci --workspace @memeguard/frontend --include-workspace-root=false --no-audit --no-fund
COPY packages/shared packages/shared
COPY apps/frontend apps/frontend
RUN npm run build --workspace @memeguard/frontend

FROM nginx:1.27-alpine
COPY apps/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/apps/frontend/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=15s --timeout=5s --retries=5 CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
