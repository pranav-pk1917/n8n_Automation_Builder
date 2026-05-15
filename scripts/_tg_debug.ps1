# _tg_debug.ps1
# Step 1: Confirms the bot token is valid (getMe).
# Step 2: Calls getUpdates to discover the group chat ID.
# Run AFTER adding @webley_seotools_hitl_bot to a group and sending at least one message.
# Usage: powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/_tg_debug.ps1"

param(
    [string]$BotToken = "8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac"
)

$base = "https://api.telegram.org/bot$BotToken"

# -------------------------------------------------------
# 1. getMe — confirms the token is valid
# -------------------------------------------------------
Write-Host ""
Write-Host "=== Step 1: getMe (bot health check) ===" -ForegroundColor Cyan
try {
    $me = Invoke-RestMethod -Uri "$base/getMe"
    if ($me.ok) {
        Write-Host "PASS  Bot is alive and token is valid" -ForegroundColor Green
        Write-Host "  id               : $($me.result.id)"
        Write-Host "  username         : @$($me.result.username)"
        Write-Host "  name             : $($me.result.first_name)"
        Write-Host "  can_join_groups  : $($me.result.can_join_groups)"
    } else {
        Write-Host "FAIL  getMe returned ok=false. Token is probably invalid." -ForegroundColor Red
        Write-Host ($me | ConvertTo-Json -Depth 5)
        exit 1
    }
} catch {
    Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# -------------------------------------------------------
# 2. getUpdates — finds the group chat ID
# -------------------------------------------------------
Write-Host ""
Write-Host "=== Step 2: getUpdates (find group chat ID) ===" -ForegroundColor Cyan
try {
    $r = Invoke-RestMethod -Uri "$base/getUpdates"

    if ($r.ok -and $r.result.Count -gt 0) {
        Write-Host "Found $($r.result.Count) update(s):" -ForegroundColor Green
        $found = $false
        foreach ($upd in $r.result) {
            $msg = $upd.message
            if ($msg) {
                $found = $true
                Write-Host ("  chat_id={0}  type={1}  title={2}  from=@{3}  text={4}" -f `
                    $msg.chat.id, $msg.chat.type, $msg.chat.title, $msg.from.username, $msg.text) -ForegroundColor Green
            }
        }
        if ($found) {
            Write-Host ""
            Write-Host "ACTION: Copy the chat_id above, paste it into step 8.10 of the setup guide," -ForegroundColor Cyan
            Write-Host "then run verify_services.ps1 with that chat ID to complete the Telegram verify." -ForegroundColor Cyan
        }
    } elseif ($r.ok -and $r.result.Count -eq 0) {
        Write-Host "EMPTY - no updates returned." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The bot token is valid (Step 1 passed), but the group is not set up yet." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Do these 3 things in Telegram, then re-run this script:" -ForegroundColor Cyan
        Write-Host "  1. Create a group named: SEO-Tools HITL"
        Write-Host "  2. Add @webley_seotools_hitl_bot to the group"
        Write-Host "  3. Send any message in the group (e.g. type 'hello' and send)"
        Write-Host ""
        Write-Host "Note: if you already added the bot but forgot to send a message, just send" -ForegroundColor DarkGray
        Write-Host "any message now and re-run this script immediately." -ForegroundColor DarkGray
    } else {
        Write-Host "FAIL  Telegram returned ok=false:" -ForegroundColor Red
        Write-Host ($r | ConvertTo-Json -Depth 5)
    }
} catch {
    Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
}
