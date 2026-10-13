$response = Invoke-RestMethod -Uri "http://127.0.0.1:8088/api/v1/targets" -Headers @{Host="prometheus.local"}
Write-Host "=== Active Targets: $($response.data.activeTargets.Count) ===" -ForegroundColor Cyan
foreach ($t in $response.data.activeTargets) {
    Write-Host "Target: $($t.scrapeUrl) | Health: $($t.health) | Namespace: $($t.labels.namespace) | Pod: $($t.labels.pod) | Error: $($t.lastError)"
}
