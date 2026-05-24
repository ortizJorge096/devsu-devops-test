#!/usr/bin/env bash
# local-deploy.sh — build the image inside minikube's docker daemon (so
# kubelet finds it without a registry pull) and apply the `local`
# overlay. Idempotent — re-run after code changes.
#
# Usage:
#   scripts/local-deploy.sh                # builds demo-devops-nodejs:dev
#   TAG=feature-xyz scripts/local-deploy.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${TAG:-dev}"

if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then
  echo "→ Using minikube's docker daemon"
  eval "$(minikube docker-env)"
else
  echo "→ minikube not detected — falling back to the host docker daemon"
  echo "  (docker-desktop / kind / k3d users: that's the expected path)"
fi

echo "→ Building image demo-devops-nodejs:${TAG}"
docker build -t "demo-devops-nodejs:${TAG}" "${ROOT}/app"

echo "→ Applying Kustomize overlay (local)"
kubectl apply -k "${ROOT}/k8s/overlays/local"

echo "→ Waiting for rollout"
kubectl -n demo-devops rollout status deploy/demo-devops --timeout=120s

echo "→ Pods, HPA, ingress:"
kubectl -n demo-devops get pods,hpa,ingress

cat <<EOF

Done.
Add this to /etc/hosts if you haven't:
  $(minikube ip 2>/dev/null || echo 127.0.0.1)  demo-devops.local

Then:
  curl http://demo-devops.local/health
  curl http://demo-devops.local/api/users

Or, if your local cluster doesn't expose an ingress controller, run:
  scripts/port-forward.sh
EOF
