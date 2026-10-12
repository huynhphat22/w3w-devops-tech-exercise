#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="w3w-cluster"

echo "=== Tearing down Kubernetes Cluster: ${CLUSTER_NAME} ==="

if command -v k3d &> /dev/null && k3d cluster list | grep -q "^${CLUSTER_NAME}\b"; then
  k3d cluster delete "${CLUSTER_NAME}"
elif command -v kind &> /dev/null && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "Cluster '${CLUSTER_NAME}' not found."
fi

echo "=== Cluster destroyed ==="
