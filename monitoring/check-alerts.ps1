$response = Invoke-RestMethod -Uri "http://127.0.0.1:8088/api/v1/rules" -Headers @{Host="prometheus.local"}
Write-Host "=== Rule Groups: $($response.data.groups.Count) ===" -ForegroundColor Cyan
foreach ($g in $response.data.groups) {
    Write-Host "Group: $($g.name) | File: $($g.file)"
    foreach ($r in $g.rules) {
        Write-Host "  Rule: $($r.name) | State: $($r.state) | Query: $($r.query)"
    }
}

$alerts = Invoke-RestMethod -Uri "http://127.0.0.1:8088/api/v1/alerts" -Headers @{Host="prometheus.local"}
Write-Host "`n=== Active Alerts: $($alerts.data.alerts.Count) ===" -ForegroundColor Cyan
foreach ($a in $alerts.data.alerts) {
    Write-Host "Alert: $($a.labels.alertname) | State: $($a.state) | Value: $($a.value) | ActiveSince: $($a.activeAt)"
}
