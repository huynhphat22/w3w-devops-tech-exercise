[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ClusterName = "w3w-cluster"

Write-Host "=== Tearing down Kubernetes Cluster: $ClusterName ===" -ForegroundColor Yellow

if (Get-Command k3d -ErrorAction SilentlyContinue) {
    k3d cluster delete $ClusterName
} elseif (Get-Command kind -ErrorAction SilentlyContinue) {
    kind delete cluster --name $ClusterName
} else {
    Write-Host "Cluster '$ClusterName' not found or neither CLI available."
}

Write-Host "=== Cluster destroyed ===" -ForegroundColor Green
