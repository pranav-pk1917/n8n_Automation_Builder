# verify_openrouter.ps1
# Tests all three OpenRouter model roles used in SEO-Tools Phase 1.
# Run: powershell -ExecutionPolicy Bypass -File .\verify_openrouter.ps1
# You will be prompted for the API key (not stored anywhere).

param(
    [string]$ApiKey = ""
)

if (-not $ApiKey) {
    $secure = Read-Host "Paste OpenRouter API key (sk-or-v1-...)" -AsSecureString
    $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )
}

$baseUrl = "https://openrouter.ai/api/v1"
$pass = 0
$fail = 0

function Invoke-ChatTest {
    param([string]$Model, [string]$Label)
    Write-Host ""
    Write-Host "=== Chat test: $Label ($Model) ===" -ForegroundColor Cyan
    $body = @{
        model    = $Model
        messages = @(@{ role = "user"; content = "reply with the single word ok" })
    } | ConvertTo-Json -Depth 10
    try {
        $r = Invoke-RestMethod `
            -Method Post `
            -Uri "$baseUrl/chat/completions" `
            -Headers @{ Authorization = "Bearer $ApiKey" } `
            -ContentType "application/json; charset=utf-8" `
            -Body $body
        $text = $r.choices[0].message.content
        Write-Host "PASS  response: $text" -ForegroundColor Green
        $script:pass++
    } catch {
        Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
    }
}

function Invoke-EmbeddingTest {
    param([string]$Model, [int]$Dims)
    Write-Host ""
    Write-Host "=== Embedding test: $Model (expecting $Dims dims) ===" -ForegroundColor Cyan
    $body = @{
        model      = $Model
        input      = "hello world"
        dimensions = $Dims
    } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod `
            -Method Post `
            -Uri "$baseUrl/embeddings" `
            -Headers @{ Authorization = "Bearer $ApiKey" } `
            -ContentType "application/json; charset=utf-8" `
            -Body $body
        $len = $r.data[0].embedding.Count
        if ($len -eq $Dims) {
            Write-Host "PASS  embedding length: $len" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "WARN  embedding length $len != expected $Dims" -ForegroundColor Yellow
            $script:fail++
        }
    } catch {
        Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
    }
}

Invoke-ChatTest      -Model "google/gemini-2.0-flash-001"       -Label "Primary LLM"
Invoke-EmbeddingTest -Model "openai/text-embedding-3-small"     -Dims 768
Invoke-ChatTest      -Model "openai/gpt-4o-mini"                -Label "Cross-validation LLM"

Write-Host ""
Write-Host "==============================" -ForegroundColor White
Write-Host "Results: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Write-Host "=============================="
