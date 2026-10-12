[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClusterName = "w3w-cluster"

Write-Host "=== Standing up Multi-Node Kubernetes Cluster: $ClusterName ===" -ForegroundColor Cyan

if (Get-Command k3d -ErrorAction SilentlyContinue) {
    Write-Host "Using k3d to create cluster..." -ForegroundColor Green
    $existing = k3d cluster list -o json | ConvertFrom-Json 2>$null | Where-Object { $_.name -eq $ClusterName }
    if ($existing) {
        Write-Host "Cluster '$ClusterName' already exists." -ForegroundColor Yellow
    } else {
        k3d cluster create --config "$ScriptDir\k3d.yaml"
    }
} elseif (Get-Command kind -ErrorAction SilentlyContinue) {
    Write-Host "k3d not detected; using kind to create cluster..." -ForegroundColor Green
    $existing = kind get clusters 2>$null | Where-Object { $_ -eq $ClusterName }
    if ($existing) {
        Write-Host "Cluster '$ClusterName' already exists." -ForegroundColor Yellow
    } else {
        kind create cluster --config "$ScriptDir\kind.yaml"
        Write-Host "Installing Ingress-NGINX controller for kind..." -ForegroundColor Green
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
        kubectl wait --namespace ingress-nginx `
            --for=condition=ready pod `
            --selector=app.kubernetes.io/component=controller `
            --timeout=120s
    }
} else {
    Write-Error "Error: Neither 'k3d' nor 'kind' found in PATH. Please install k3d (https://k3d.io) or kind (https://kind.sigs.k8s.io)."
    exit 1
}

Write-Host "Waiting for all cluster nodes to reach Ready state..." -ForegroundColor Cyan
kubectl wait --for=condition=Ready nodes --all --timeout=120s

Write-Host "`n=== Cluster Nodes ===" -ForegroundColor Green
kubectl get nodes -o wide

Write-Host "`n=== Cluster successfully initialized! ===" -ForegroundColor Green
