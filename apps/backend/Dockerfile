# syntax=docker/dockerfile:1
# Behind a TLS-intercepting proxy, pass its CA without baking it into a layer:
#   docker build --secret id=npm_ca,src=/path/to/ca.pem ...
# Build context: repository root (docker build -f apps/backend/Dockerfile .)

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/backend/package.json apps/backend/
COPY apps/frontend/package.json apps/frontend/
RUN --mount=type=secret,id=npm_ca,required=false \
    if [ -f /run/secrets/npm_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/npm_ca; fi; \
    npm ci --workspace @memeguard/backend --include-workspace-root=false --no-audit --no-fund
COPY packages/shared packages/shared
COPY apps/backend apps/backend
RUN npm run build --workspace @memeguard/backend

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8080 \
    LOG_PRETTY=false
WORKDIR /app
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/backend/package.json apps/backend/
COPY apps/frontend/package.json apps/frontend/
RUN --mount=type=secret,id=npm_ca,required=false \
    if [ -f /run/secrets/npm_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/npm_ca; fi; \
    npm ci --workspace @memeguard/backend --include-workspace-root=false --omit=dev --no-audit --no-fund \
    && npm cache clean --force
COPY --from=build /app/apps/backend/dist apps/backend/dist
COPY apps/backend/drizzle apps/backend/drizzle
RUN mkdir -p /app/apps/backend/data && chown -R node:node /app/apps/backend/data
WORKDIR /app/apps/backend
USER node
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:8080/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/index.js"]
