# syntax=docker/dockerfile:1.7
#
# Multi-stage Dockerfile for the Devsu Node.js users API.
#
# Stages:
#   1) deps       — install full deps for build/test reproducibility
#   2) test       — runs unit tests + coverage; build fails if tests fail
#   3) prod-deps  — only production dependencies (slim final image)
#   4) runtime    — minimal Alpine image, non-root user, healthcheck
#
# Best practices applied:
#   - Pinned base image with major version tag (node:18.19-alpine)
#   - Multi-stage build minimises final image (~150MB vs ~1GB)
#   - Non-root user (UID 10001) — Pod runs read-only friendly
#   - Built-in HEALTHCHECK so Docker can surface unhealthy containers
#   - dumb-init as PID 1 for proper signal handling (SIGTERM → graceful shutdown)
#   - NODE_ENV=production, NPM_CONFIG_LOGLEVEL=warn for clean logs
#   - Explicit EXPOSE 8000 and tini-style init

ARG NODE_VERSION=18.19-alpine

# ─── Stage 1: deps ────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION} AS deps
WORKDIR /usr/src/app
# Install build deps required by sqlite3 native bindings.
RUN apk add --no-cache python3 make g++ \
 && ln -sf python3 /usr/bin/python
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# ─── Stage 2: test (runs in CI; can be skipped locally with --target runtime) ─
FROM deps AS test
COPY . .
RUN npm run test:coverage

# ─── Stage 3: prod-deps ───────────────────────────────────────────────────────
FROM node:${NODE_VERSION} AS prod-deps
WORKDIR /usr/src/app
RUN apk add --no-cache python3 make g++ \
 && ln -sf python3 /usr/bin/python
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
 && npm cache clean --force

# ─── Stage 4: runtime ─────────────────────────────────────────────────────────
FROM node:${NODE_VERSION} AS runtime

# dumb-init = tiny PID 1 that forwards signals; wget = healthcheck client.
RUN apk add --no-cache dumb-init wget \
 && addgroup -S -g 10001 nodeapp \
 && adduser  -S -u 10001 -G nodeapp nodeapp

ENV NODE_ENV=production \
    PORT=8000 \
    NPM_CONFIG_LOGLEVEL=warn

WORKDIR /usr/src/app

# Copy production deps from prod-deps stage, then app source.
COPY --chown=nodeapp:nodeapp --from=prod-deps /usr/src/app/node_modules ./node_modules
COPY --chown=nodeapp:nodeapp . .

# SQLite needs a writable path. In K8s this is backed by an emptyDir volume.
RUN mkdir -p /usr/src/app/data \
 && chown -R nodeapp:nodeapp /usr/src/app/data
VOLUME ["/usr/src/app/data"]

USER nodeapp

EXPOSE 8000

# Container-level healthcheck — also wired to K8s liveness/readiness probes.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1:${PORT}/health || exit 1

# dumb-init forwards SIGTERM so node can shut down gracefully.
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "index.js"]
