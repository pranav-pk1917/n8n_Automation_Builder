$workerUrl   = "https://seo-tools-production-c347.up.railway.app"
$workerToken = "skayblDKeN3wULj1MimzZfCI69OvpunH"

Write-Host ""
Write-Host "=== /health ===" -ForegroundColor Cyan
$h = Invoke-RestMethod -Method Get -Uri "$workerUrl/health"
Write-Host ($h | ConvertTo-Json -Compress) -ForegroundColor Green

Write-Host ""
Write-Host "=== /cluster (full error body via WebRequest) ===" -ForegroundColor Cyan
$body = @{
    client_id                  = "11111111-1111-1111-1111-111111111111"
    pipeline_run_id            = "22222222-2222-2222-2222-222222222222"
    keyword_classification_ids = @()
} | ConvertTo-Json

try {
    $r = Invoke-WebRequest `
        -Method Post `
        -Uri "$workerUrl/cluster" `
        -Headers @{ Authorization = "Bearer $workerToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body $body `
        -UseBasicParsing
    Write-Host "HTTP $($r.StatusCode)" -ForegroundColor Green
    Write-Host $r.Content -ForegroundColor Green
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errorBody = $reader.ReadToEnd()
        Write-Host "HTTP $($resp.StatusCode.value__)" -ForegroundColor Red
        Write-Host "Body: $errorBody" -ForegroundColor Red
    } else {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== FastAPI /openapi.json (to confirm app loaded) ===" -ForegroundColor Cyan
try {
    $api = Invoke-RestMethod -Method Get -Uri "$workerUrl/openapi.json"
    Write-Host "PASS  API title: $($api.info.title) v$($api.info.version)" -ForegroundColor Green
    Write-Host "      Routes: $(($api.paths.PSObject.Properties.Name) -join ', ')"
} catch {
    Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
}
