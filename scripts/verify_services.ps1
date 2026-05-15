# verify_services.ps1
# Tests Slack bot posting, SerpAPI key, and Telegram bot.
# Run: powershell -ExecutionPolicy Bypass -File .\verify_services.ps1
#
# Pass "skip" for any service you do not want to test.
# Example (Slack only):
#   .\verify_services.ps1 -SlackBotToken "xoxb-..." -SlackChannelId "C0B..." -SerpApiKey skip -TelegramBotToken skip
# Example (Telegram only):
#   .\verify_services.ps1 -TelegramBotToken "123:AAH..." -TelegramChatId "-100..." -SlackBotToken skip -SerpApiKey skip

param(
    [string]$SlackBotToken    = "",
    [string]$SlackChannelId   = "",
    [string]$SerpApiKey       = "",
    [string]$TelegramBotToken = "",
    [string]$TelegramChatId   = ""
)

$pass = 0
$fail = 0

# --------------------------------------------------------------------------
# Slack
# --------------------------------------------------------------------------
if ($SlackBotToken -eq "skip") {
    Write-Host ""
    Write-Host "=== Slack: SKIPPED ===" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "=== Slack: post message to channel ===" -ForegroundColor Cyan

    if (-not $SlackBotToken) {
        $SlackBotToken = Read-Host "Slack Bot Token (xoxb-...)"
    }
    if (-not $SlackChannelId) {
        $SlackChannelId = Read-Host "Slack Channel ID (e.g. C0B43A7QG5P)"
    }

    $slackBody = @{
        channel = $SlackChannelId
        text    = "setup verification test from intern setup guide"
    } | ConvertTo-Json

    try {
        $r = Invoke-RestMethod `
            -Method Post `
            -Uri "https://slack.com/api/chat.postMessage" `
            -Headers @{ Authorization = "Bearer $SlackBotToken" } `
            -ContentType "application/json; charset=utf-8" `
            -Body $slackBody
        if ($r.ok -eq $true) {
            Write-Host "PASS  message posted to channel $($r.channel)" -ForegroundColor Green
            $pass++
        } else {
            Write-Host "FAIL  Slack API returned ok=false, error=$($r.error)" -ForegroundColor Red
            $fail++
        }
    } catch {
        Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

# --------------------------------------------------------------------------
# SerpAPI
# --------------------------------------------------------------------------
if ($SerpApiKey -eq "skip") {
    Write-Host ""
    Write-Host "=== SerpAPI: SKIPPED ===" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "=== SerpAPI: test search ===" -ForegroundColor Cyan

    if (-not $SerpApiKey) {
        $SerpApiKey = Read-Host "SerpAPI Key"
    }

    try {
        $r2 = Invoke-RestMethod -Uri "https://serpapi.com/search.json" -Method Get -Body @{
            q       = "test"
            api_key = $SerpApiKey
            num     = "1"
        }
        if ($r2.search_metadata) {
            Write-Host "PASS  search_metadata.status = $($r2.search_metadata.status)" -ForegroundColor Green
            $pass++
        } else {
            Write-Host "WARN  response received but no search_metadata field" -ForegroundColor Yellow
            $fail++
        }
    } catch {
        Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

# --------------------------------------------------------------------------
# Telegram
# --------------------------------------------------------------------------
if ($TelegramBotToken -eq "skip") {
    Write-Host ""
    Write-Host "=== Telegram: SKIPPED ===" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "=== Telegram: send message to group ===" -ForegroundColor Cyan

    if (-not $TelegramBotToken) {
        $TelegramBotToken = Read-Host "Telegram Bot Token (123456789:AAH...)"
    }
    if (-not $TelegramChatId) {
        $TelegramChatId = Read-Host "Telegram Chat ID (negative number, e.g. -1001234567890)"
    }

    $tgBody = @{
        chat_id = $TelegramChatId
        text    = "setup verification test from intern setup guide"
    } | ConvertTo-Json

    try {
        $r3 = Invoke-RestMethod `
            -Method Post `
            -Uri "https://api.telegram.org/bot$TelegramBotToken/sendMessage" `
            -ContentType "application/json; charset=utf-8" `
            -Body $tgBody
        if ($r3.ok -eq $true) {
            Write-Host "PASS  message sent, message_id=$($r3.result.message_id)" -ForegroundColor Green
            $pass++
        } else {
            Write-Host "FAIL  Telegram returned ok=false, description=$($r3.description)" -ForegroundColor Red
            $fail++
        }
    } catch {
        Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "==============================" -ForegroundColor White
Write-Host "Results: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Write-Host "=============================="
