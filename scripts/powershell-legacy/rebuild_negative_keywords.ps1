# Rebuild negative_keywords.md - Keep only confirmed negatives
# Being conservative: if uncertain, keep as negative (safe approach)

# NEGATIVE patterns (information/research intent = IS negative)
$negativePatterns = @(
    # HOSPITALS/MEDICAL
    "hospital", "hospitals", "medical center", "clinic", "clinics",
    "healthcare facility", "health system", "health network",
    # RANKINGS
    "rankings", "ranking", "top 10", "top 20", "top 50", "top 100",
    "best hospitals", "best medical", "best healthcare",
    "top hospitals", "top medical", "top healthcare",
    "best places to work", "best places to retire",
    "best states for", "top states for",
    # EDUCATION/CAREER
    "nursing program", "residency", "medical school", "mba",
    "emba", "degree program", "training program", "pa program",
    # MOVIE/RATINGS
    "imdb", "rottentomatoes", "movie rating", "netflix",
    "hulu", "disney+", "prime video", "hbomax",
    # PREGNANCY/FERTILITY
    "clearblue", "pregnancy test", "ovulation", "fertility",
    # CALL CENTER/IVR
    "ivr", "auto dialer", "predictive dialer", "call center",
    "contact center", "dialer system", "telephony",
    # TECHNICAL/DEVELOPER
    "how to ", "tutorial", "learn ", "course ", "training",
    "stackoverflow", "github", "npm", "pip", "install",
    "download", "free software",
    # MEDICAL CONDITIONS
    "symptoms", "treatment for", "diagnosis", "medication for",
    "cure for", "remedies",
    # NEWS/M&A
    "news", "merger", "acquisition", "layoffs", "ceo",
    # JOB SEARCH
    "jobs", "careers", "hiring", "job board", "job opening",
    "places to retire", "fastest growing state", "retire in"
)

function Test-IsNegative {
    param([string]$keyword)

    $kw = $keyword.ToLower().Trim()

    # Skip headers/comments
    if ([string]::IsNullOrWhiteSpace($kw)) { return $false }
    if ($kw -match "^(#|##|- |\*\*|\d+\.)") { return $false }
    if ($kw.Length -lt 3) { return $false }

    # Check NEGATIVE patterns
    foreach ($pattern in $negativePatterns) {
        if ($kw -match $pattern) {
            return $true
        }
    }

    return $false
}

# Read original file
$content = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md"

$kept = @()
$removed = @()

foreach ($line in $content) {
    if (Test-IsNegative -keyword $line) {
        $kept += $line
    } else {
        $removed += $line
    }
}

Write-Host "=== REBUILD RESULTS ===" -ForegroundColor Cyan
Write-Host "Kept as negative: $($kept.Count)" -ForegroundColor Red
Write-Host "Removed (service buyers): $($removed.Count)" -ForegroundColor Green
Write-Host ""

# Write new file
$kept | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords_REBUILT.md" -Encoding UTF8
$removed | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\service_buyer_keywords.txt" -Encoding UTF8

Write-Host "Files created:" -ForegroundColor Cyan
Write-Host "  negative_keywords_REBUILT.md - Only confirmed negatives ($($kept.Count))"
Write-Host "  service_buyer_keywords.txt - Keywords removed ($($removed.Count))"

Write-Host ""
Write-Host "SAMPLE Kept (first 20):" -ForegroundColor Red
$kept | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "SAMPLE Removed (first 20):" -ForegroundColor Green
$removed | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }