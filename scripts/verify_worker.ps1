# verify_worker.ps1
# Tests the Railway-hosted Python clustering worker.
# Run: powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_worker.ps1" -WorkerUrl "https://..." -WorkerToken "your-32-char-token"

param(
    [string]$WorkerUrl   = "",
    [string]$WorkerToken = ""
)

if (-not $WorkerUrl) {
    $WorkerUrl = Read-Host "Worker public URL (e.g. https://seo-tools-production-c347.up.railway.app)"
}
if (-not $WorkerToken) {
    $WorkerToken = Read-Host "WORKER_AUTH_TOKEN (32-char random string)"
}

$pass = 0
$fail = 0

# -------------------------------------------------------
# 1. Health check (no auth required)
# -------------------------------------------------------
Write-Host ""
Write-Host "=== Health check ===" -ForegroundColor Cyan
try {
    $r = Invoke-RestMethod -Method Get -Uri "$WorkerUrl/health"
    if ($r.ok -eq $true) {
        Write-Host "PASS  $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "FAIL  ok=false: $($r | ConvertTo-Json -Compress)" -ForegroundColor Red
        $fail++
    }
} catch {
    Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
    $fail++
}

# -------------------------------------------------------
# 2. Cluster endpoint — empty payload, auth test
# -------------------------------------------------------
Write-Host ""
Write-Host "=== Cluster endpoint (empty payload auth test) ===" -ForegroundColor Cyan
$body = @{
    client_id                  = "11111111-1111-1111-1111-111111111111"
    pipeline_run_id            = "22222222-2222-2222-2222-222222222222"
    keyword_classification_ids = @()
} | ConvertTo-Json

try {
    $r2 = Invoke-RestMethod `
        -Method Post `
        -Uri "$WorkerUrl/cluster" `
        -Headers @{ Authorization = "Bearer $WorkerToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body $body
    $clusterCount = $r2.clusters.Count
    $unclusteredCount = $r2.unclustered_count
    Write-Host "PASS  clusters=$clusterCount, unclustered=$unclusteredCount" -ForegroundColor Green
    $pass++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401 -or $code -eq 403) {
        Write-Host "FAIL  Auth rejected (HTTP $code) - WORKER_AUTH_TOKEN mismatch" -ForegroundColor Red
    } else {
        Write-Host "FAIL  HTTP ${code}: $($_.Exception.Message)" -ForegroundColor Red
    }
    $fail++
}

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
Write-Host ""
Write-Host "==============================" -ForegroundColor White
Write-Host "Results: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Write-Host "=============================="
