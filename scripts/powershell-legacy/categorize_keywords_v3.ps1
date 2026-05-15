# Keyword Categorization Tool v3 - User Intent Focus
# If user is LOOKING TO HIRE marketing services = NOT negative
# If user is RESEARCHING/INFORMATION = IS negative

# SERVICE patterns (user intent = hire services) - NOT negative keywords
$servicePatterns = @(
    # Direct service types
    "marketing", "seo ", "seo/", "ppc ", "paid search", "paid social",
    "social media marketing", "content marketing", "email marketing",
    "web development", "app development", "mobile app", "website design",
    "ux design", "ui design", "user experience design", "web design",
    "ecommerce", "shopify", "woocommerce", "wordpress",
    "crm ", "marketing automation", "hubspot", "salesforce",
    "ai chatbot", "chatbot development", "marketing platform",
    "advertising", "creative agency", "branding", "lead generation",
    # Hiring/service buyer signals
    "agency", "company for", "services for", "provider for",
    "hire ", "outsourcing", "outstaff", "dedicated",
    "consultant for", "consulting for", "specialist for",
    # These with "for" often = service buyer
    "marketing for", "seo for", "web design for", "development for"
)

# NEGATIVE patterns (user intent = NOT hire services) - IS negative keywords
$negativePatterns = @(
    # RANKINGS/LISTS - research intent
    "best hospitals", "top hospitals", "top 10 hospitals", "top 20 ",
    "hospital rankings", "hospital rating", "hospital compare",
    "best nursing", "top nursing", "best medical", "top medical",
    "best universities", "top universities", "university rankings",
    "best schools", "school rankings", "program rankings",
    # MOVIE/RATINGS
    "imdb", "rottentomatoes", "movie rating", "film rating",
    "netflix", "hulu", "disney+", "amazon prime", "hbomax",
    # PREGNANCY/FERTILITY PRODUCTS
    "clearblue", "pregnancy test", "ovulation test", "fertility monitor",
    "first response", "predictor test", "clear blue",
    # CALL CENTER/IVR - operational software, not marketing
    "ivr ", "auto dialer", "predictive dialer", "call center software",
    "contact center solution", "dialer system", "telephony solution",
    # PROGRAMMING/TECHNICAL - development intent
    " how to ", "tutorial for", "learn ", "course for",
    "stackoverflow", "github.com/", "npm ", "pip install",
    "sudo apt", "brew install", "download ", "free download",
    # MEDICAL CONDITIONS - health information intent
    "symptoms of", "treatment for", "diagnosis for", "medication for",
    "cure for", "remedies for", "home remedy",
    # NEWS/INDUSTRY INFO
    "news today", "industry news", "healthcare news", "hospital news",
    "merger ", "acquisition ", "layoffs ", "ceo resignation",
    # JOB SEARCH
    "jobs in", "careers in", "job openings", "hiring ",
    "nursing jobs", "hospital jobs", "medical jobs",
    # SPECIFIC SOFTWARE categories
    "insurance software", "pharmacy software", "medical software",
    "clinical trial software", "hospital management system"
)

function Test-KeywordIntent {
    param([string]$keyword)

    $kw = $keyword.ToLower().Trim()

    # Skip empty, headers, comments
    if ([string]::IsNullOrWhiteSpace($kw)) { return "SKIP" }
    if ($kw -match "^(#|##|- |\* |\*\*|\d+\.)") { return "SKIP" }

    # Check SERVICE patterns = potential client looking to hire
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

Write-Host "=== CATEGORIZATION RESULTS (v3) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "SERVICE_BUYER (NOT negative - potential clients): $($serviceBuyers.Count)" -ForegroundColor Green
Write-Host "NEGATIVE (IS negative - information intent): $($negatives.Count)" -ForegroundColor Red
Write-Host "NEEDS REVIEW (uncertain): $($needsReview.Count)" -ForegroundColor Yellow
Write-Host ""

Write-Host "=== SAMPLE SERVICE_BUYER (first 40) ===" -ForegroundColor Green
$serviceBuyers | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE NEGATIVE (first 40) ===" -ForegroundColor Red
$negatives | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE NEEDS REVIEW (first 40) ===" -ForegroundColor Yellow
$needsReview | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }

# Export
$serviceBuyers | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\remove_from_negative.txt" -Encoding UTF8
$negatives | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\keep_as_negative.txt" -Encoding UTF8
$needsReview | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\review_later.txt" -Encoding UTF8

Write-Host ""
Write-Host "Export complete:" -ForegroundColor Cyan
Write-Host "  remove_from_negative.txt ($($serviceBuyers.Count))"
Write-Host "  keep_as_negative.txt ($($negatives.Count))"
Write-Host "  review_later.txt ($($needsReview.Count))"