#!/usr/bin/env bash
# port-forward.sh — expose the Service on localhost when there's no
# ingress controller available (handy for docker-desktop without the
# ingress addon, or for quick smoke tests against the prod cluster).
#
# Usage:
#   scripts/port-forward.sh                     # defaults: demo-devops / svc/demo-devops 8080:80
#   NAMESPACE=demo-devops-dev scripts/port-forward.sh
#   LOCAL_PORT=9090 scripts/port-forward.sh
set -euo pipefail

NAMESPACE="${NAMESPACE:-demo-devops}"
SERVICE="${SERVICE:-demo-devops}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
REMOTE_PORT="${REMOTE_PORT:-80}"

echo "→ kubectl -n ${NAMESPACE} port-forward svc/${SERVICE} ${LOCAL_PORT}:${REMOTE_PORT}"
echo "  Health: http://localhost:${LOCAL_PORT}/health"
echo "  Users : http://localhost:${LOCAL_PORT}/api/users"

exec kubectl -n "${NAMESPACE}" port-forward "svc/${SERVICE}" "${LOCAL_PORT}:${REMOTE_PORT}"
