[CmdletBinding()]
param(
    [string]$TargetHost = "dev.greeter.local",
    [int]$BoomCount = 30,
    [int]$MaxWaitSeconds = 60
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Extension B: Alert Demonstration (/boom)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Initial State
Write-Host "`n[Step 1] Checking baseline alert state in Prometheus..." -ForegroundColor Yellow
$targetNamespace = if ($TargetHost -like "prod*") { "prod" } else { "dev" }
$initial = Invoke-RestMethod -Uri "http://127.0.0.1:8088/api/v1/alerts" -Headers @{Host="prometheus.local"}
$activeAlerts = @($initial.data.alerts | Where-Object { 
    $_.labels.alertname -eq "GreeterHighHttp5xxErrorRate" -and 
    $_.labels.namespace -eq $targetNamespace 
})
if ($activeAlerts.Count -gt 0) {
    Write-Host "Alert already active in namespace '$targetNamespace': $($activeAlerts[0].state)" -ForegroundColor Yellow
} else {
    Write-Host "Baseline confirmed: Alert 'GreeterHighHttp5xxErrorRate' in namespace '$targetNamespace' is INACTIVE." -ForegroundColor Green
}

# 2. Trigger Outage via /boom
Write-Host "`n[Step 2] Sending $BoomCount simulated failure requests to /boom (Host: $TargetHost)..." -ForegroundColor Yellow
for ($i = 1; $i -le $BoomCount; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:8088/boom" -Headers @{Host=$TargetHost} -TimeoutSec 2 -ErrorAction SilentlyContinue
    } catch {
        # Expected HTTP 500
    }
    Start-Sleep -Milliseconds 100
}
Write-Host "Dispatched $BoomCount failure requests to /boom." -ForegroundColor Green

# 3. Monitor Alert Transition
Write-Host "`n[Step 3] Monitoring Prometheus alert state (waiting for pending -> firing)..." -ForegroundColor Yellow
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$fired = $false

while ($stopwatch.Elapsed.TotalSeconds -lt $MaxWaitSeconds) {
    $alerts = Invoke-RestMethod -Uri "http://127.0.0.1:8088/api/v1/alerts" -Headers @{Host="prometheus.local"}
    $matchingAlerts = @($alerts.data.alerts | Where-Object { 
        $_.labels.alertname -eq "GreeterHighHttp5xxErrorRate" -and 
        $_.labels.namespace -eq $targetNamespace 
    })
    
    if ($matchingAlerts.Count -gt 0) {
        $alert = $matchingAlerts[0]
        $state = $alert.state
        $ns = $alert.labels.namespace
        $val = [double]$alert.value
        Write-Host ("[{0:D2}s] Alert state: {1} | Namespace: {2} | Observed Error Rate: {3:F1}%" -f [int]$stopwatch.Elapsed.TotalSeconds, $state.ToUpper(), $ns, $val) -ForegroundColor Cyan
        
        if ($state -eq "firing") {
            $fired = $true
            break
        }
    } else {
        Write-Host ("[{0:D2}s] Waiting for metrics evaluation..." -f [int]$stopwatch.Elapsed.TotalSeconds)
    }

    # Keep sending background trickle to sustain the 1-minute rate window
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:8088/boom" -Headers @{Host=$TargetHost} -TimeoutSec 2 -ErrorAction SilentlyContinue
    } catch {}

    Start-Sleep -Seconds 5
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($fired) {
    Write-Host " SUCCESS: Alert 'GreeterHighHttp5xxErrorRate' successfully reached FIRING state!" -ForegroundColor Green
    Write-Host "Alert Details:" -ForegroundColor Green
    $alert | ConvertTo-Json -Depth 5 | Write-Host
} else {
    Write-Error "Timeout reached without alert transitioning to FIRING."
}
Write-Host "==========================================================" -ForegroundColor Cyan
