#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="w3w-cluster"

echo "=== Standing up Multi-Node Kubernetes Cluster: ${CLUSTER_NAME} ==="

if command -v k3d &> /dev/null; then
  echo "Using k3d to create cluster..."
  if k3d cluster list | grep -q "^${CLUSTER_NAME}\b"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
  else
    k3d cluster create --config "${SCRIPT_DIR}/k3d.yaml"
  fi
  if docker image inspect greeter:test &> /dev/null; then
    echo "Importing local image 'greeter:test' into ${CLUSTER_NAME}..."
    k3d image import greeter:test -c "${CLUSTER_NAME}"
  fi
elif command -v kind &> /dev/null; then
  echo "k3d not detected; using kind to create cluster..."
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
  else
    kind create cluster --config "${SCRIPT_DIR}/kind.yaml"
    echo "Installing Ingress-NGINX controller for kind..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=120s
  fi
  if docker image inspect greeter:test &> /dev/null; then
    echo "Importing local image 'greeter:test' into ${CLUSTER_NAME}..."
    kind load docker-image greeter:test --name "${CLUSTER_NAME}"
  fi
else
  echo "Error: Neither 'k3d' nor 'kind' found in PATH." >&2
  echo "Please install k3d (https://k3d.io) or kind (https://kind.sigs.k8s.io)." >&2
  exit 1
fi

echo "Waiting for all cluster nodes to reach Ready state..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

if command -v k3d &> /dev/null; then
  echo "Configuring Traefik Ingress Controller for High Availability (2 replicas)..."
  kubectl wait --namespace kube-system --for=condition=available deployment/traefik --timeout=120s
  kubectl scale deployment traefik -n kube-system --replicas=2
fi

echo "=== Cluster Nodes ==="
kubectl get nodes -o wide

echo "=== Cluster successfully initialized! ==="
