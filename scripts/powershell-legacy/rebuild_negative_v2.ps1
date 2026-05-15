# Rebuild negative_keywords.md - Only keep actual negative keyword lines
# Being conservative: if uncertain = negative (safe approach)

# NEGATIVE patterns (information/research intent = IS negative)
$negativePatterns = @(
    # HOSPITALS/MEDICAL FACILITIES
    "hospital", "hospitals", "medical center", "clinic", "clinics",
    "healthcare facility", "health system", "health network",
    # RANKINGS/LISTS
    "rankings", "ranking", "top 10", "top 20", "top 50", "top 100",
    "best hospitals", "best medical", "best healthcare",
    "top hospitals", "top medical", "top healthcare",
    "best places to work", "best places to retire",
    "best states for", "top states for",
    # EDUCATION/CAREER PROGRAMS
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
    # TECHNICAL/DEVELOPER INFO
    "how to ", "tutorial", "learn ", "course ", "training",
    "stackoverflow", "github", "npm", "pip", "install",
    "download", "free software",
    # MEDICAL CONDITIONS/INFO
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

    # Skip if empty
    if ([string]::IsNullOrWhiteSpace($kw)) { return $false }
    # Only process lines that are actual keywords (no headers starting with #, ##, -, *, etc.)
    if ($kw -match "^(#|##|\*|- |\*\*|\d+\.)") { return $false }
    # Skip lines that are just headers or short text
    if ($kw.Length -lt 5) { return $false }

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
$keptHeaders = @()

$inKeywordSection = $false

foreach ($line in $content) {
    # Keep all header/formatting lines
    if ($line -match "^(#|##|\*|- |\*\*|\d+\.)" -or [string]::IsNullOrWhiteSpace($line)) {
        $keptHeaders += $line
        $kept += $line
        if ($line -match "## Negative Keywords") {
            $inKeywordSection = $true
        }
        continue
    }

    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        $kept += $line
        continue
    }

    # This is an actual keyword line
    if (Test-IsNegative -keyword $trimmed) {
        $kept += $line
    } else {
        $removed += $line
    }
}

Write-Host "=== REBUILD RESULTS ===" -ForegroundColor Cyan
Write-Host "Lines kept (negative keywords): $($kept.Count)" -ForegroundColor Red
Write-Host "Lines removed (service buyers): $($removed.Count)" -ForegroundColor Green
Write-Host ""

# Write new file
$kept | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords_CLEANED.md" -Encoding UTF8
$removed | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\removed_keywords.txt" -Encoding UTF8

Write-Host "Files created:" -ForegroundColor Cyan
Write-Host "  negative_keywords_CLEANED.md - Cleaned negative keywords ($($kept.Count))"
Write-Host "  removed_keywords.txt - Removed as service buyers ($($removed.Count))"

Write-Host ""
Write-Host "SAMPLE Removed (first 25):" -ForegroundColor Green
$removed | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }