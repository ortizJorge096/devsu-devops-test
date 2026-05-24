#!/usr/bin/env bash
# k8s-deploy.sh — apply a Kustomize overlay against the local k3s cluster.
#
# This script is the manual / break-glass equivalent of what the CI/CD
# `deploy` job does on the self-hosted runner. Run it from a shell on the
# k3s host (open one with `aws ssm start-session ...`):
#
#   sudo bash scripts/k8s-deploy.sh <overlay> <namespace> <image> <branch>
#
# Example:
#   sudo bash scripts/k8s-deploy.sh dev demo-devops-dev \
#     123456789012.dkr.ecr.us-east-1.amazonaws.com/devsu-devops-nodejs:sha-abc1234 \
#     develop
#
# The pipeline itself doesn't call this script — it runs `kustomize build
# | kubectl apply -f -` inline on the runner. The script stays in-repo so
# the deploy is reproducible by hand if the runner is down.
set -euo pipefail

OVERLAY="${1:?overlay required (dev|prod)}"
NS="${2:?namespace required (demo-devops|demo-devops-dev)}"
IMG="${3:?image required (full ECR ref:tag)}"
BRANCH="${4:?branch required (main|develop)}"
KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

echo "[deploy] overlay=$OVERLAY ns=$NS img=$IMG branch=$BRANCH"

# 1) Wait for k3s apiserver (up to 10 min — first boot is slow on t3.micro).
echo "[deploy] Waiting for k3s..."
for i in $(seq 1 60); do
  if kubectl --kubeconfig "$KUBECONFIG" get nodes 2>/dev/null | grep -q ' Ready '; then
    break
  fi
  echo "  [$i/60] not ready yet..."
  if [ "$i" -eq 60 ]; then
    echo "ERROR: k3s did not become ready in 10 minutes" >&2
    exit 1
  fi
  sleep 10
done
echo "[deploy] k3s ready"

# 2) Pin the image in the overlay and apply.
echo "[deploy] Applying k8s/overlays/${OVERLAY}..."
pushd "k8s/overlays/${OVERLAY}" >/dev/null
kustomize edit set image "devsu-devops-nodejs=${IMG}"
popd >/dev/null

kustomize build "k8s/overlays/${OVERLAY}" \
  | kubectl --kubeconfig "$KUBECONFIG" apply -f -

# 3) Wait for rollout (matches the pipeline's `rollout status`).
echo "[deploy] Waiting for rollout..."
kubectl --kubeconfig "$KUBECONFIG" \
  -n "$NS" rollout status deployment/demo-devops --timeout=300s

echo "[deploy] Done. Branch=${BRANCH}"
