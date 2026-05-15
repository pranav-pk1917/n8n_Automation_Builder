# Keyword Categorization v5 - Complete Pattern Matching

# SERVICE patterns (potential client = NOT negative)
$servicePatterns = @(
    "marketing", "seo", "ppc", "paid search", "paid social",
    "social media", "content marketing", "email marketing",
    "web development", "app development", "mobile app", "website design",
    "ux design", "ui design", "user experience", "web design",
    "ecommerce", "shopify", "woocommerce", "wordpress",
    "crm", "marketing automation", "hubspot", "salesforce",
    "ai chatbot", "chatbot", "marketing platform",
    "advertising", "creative agency", "branding", "lead generation",
    "agency", "company for", "services for", "provider for",
    "hire ", "outsourcing", "outstaff", "dedicated",
    "consultant for", "consulting for", "specialist for",
    "development company", "development services", "development agency"
)

# NEGATIVE patterns (information/research/job intent = IS negative)
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

function Test-KeywordIntent {
    param([string]$keyword)

    $kw = $keyword.ToLower().Trim()

    # Skip headers/comments
    if ([string]::IsNullOrWhiteSpace($kw)) { return "SKIP" }
    if ($kw -match "^(#|##|- |\*\*|\d+\.)") { return "SKIP" }
    if ($kw.Length -lt 3) { return "SKIP" }

    # Check SERVICE patterns = potential client
    foreach ($pattern in $servicePatterns) {
        if ($kw -match $pattern) {
            return "SERVICE_BUYER"
        }
    }

    # Check NEGATIVE patterns = information/research intent
    foreach ($pattern in $negativePatterns) {
        if ($kw -match $pattern) {
            return "NEGATIVE"
        }
    }

    return "REVIEW"
}

$content = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md"

$serviceBuyers = @()
$negatives = @()
$needsReview = @()

foreach ($line in $content) {
    $result = Test-KeywordIntent -keyword $line
    switch ($result) {
        "SERVICE_BUYER" { $serviceBuyers += $line }
        "NEGATIVE" { $negatives += $line }
        "REVIEW" { $needsReview += $line }
    }
}

Write-Host "=== FINAL CATEGORIZATION ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "SERVICE_BUYER (potential clients - NOT negative): $($serviceBuyers.Count)" -ForegroundColor Green
Write-Host "NEGATIVE (information intent - IS negative): $($negatives.Count)" -ForegroundColor Red
Write-Host "NEEDS REVIEW (uncertain): $($needsReview.Count)" -ForegroundColor Yellow
Write-Host ""

Write-Host "=== SAMPLE SERVICE_BUYER (first 25) ===" -ForegroundColor Green
$serviceBuyers | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE NEGATIVE (first 25) ===" -ForegroundColor Red
$negatives | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE NEEDS REVIEW (first 25) ===" -ForegroundColor Yellow
$needsReview | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }

# Export
$serviceBuyers | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\remove_from_negative.txt" -Encoding UTF8
$negatives | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\keep_as_negative.txt" -Encoding UTF8
$needsReview | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\review_later.txt" -Encoding UTF8

Write-Host ""
Write-Host "Files exported:" -ForegroundColor Cyan
Write-Host "  remove_from_negative.txt ($($serviceBuyers.Count))"
Write-Host "  keep_as_negative.txt ($($negatives.Count))"
Write-Host "  review_later.txt ($($needsReview.Count))"