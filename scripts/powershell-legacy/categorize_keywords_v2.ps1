# Keyword Categorization Tool v2 - Focus on User Intent
# Clear intent = Service Buyer (NOT negative) vs Everything Else (might be negative)

# Service-related patterns that indicate user is LOOKING TO HIRE/HIRED services
# These are NOT negative keywords (potential clients)
$servicePatterns = @(
    # Explicit service hiring
    "seo service", "seo services", "web development service", "app development service",
    "marketing service", "marketing services", "design service", "design services",
    "development service", "development services", "consulting service", "consulting services",
    "agency", "company", "provider", "vendor",
    # Explicit service types
    "marketing agency", "design agency", "development agency", "seo agency",
    "web design", "website design", "web development", "app development",
    "mobile app", "digital marketing", "social media marketing",
    "content marketing", "performance marketing", "ppc ", "paid search",
    "marketing automation", "email marketing", "marketing consultant",
    "marketing platform", "advertising agency", "creative agency",
    "branding agency", "lead generation", "marketing software",
    # Keywords with "for" often indicate service buyer
    " services for ", " agency for ", " company for ", " provider for ",
    # Hiring/buying signals
    "hire ", "outsourcing", "outstaff", "dedicated team",
    "freelance developer", "contract developer",
    # eCommerce/SaaS specific
    "shopify development", "wordpress development", "woocommerce",
    "saas development", "saas marketing", "saas seo",
    # CRM/Automation
    "crm implementation", "marketing automation", "hubspot", "salesforce setup",
    # UX/Design
    "ux design", "ui design", "user experience design", "website redesign",
    "landing page design", "ui/ux"
)

# CLEAR NEGATIVE patterns (user intent is NOT to hire marketing services)
# These ARE negative keywords
$negativePatterns = @(
    # Consumer product purchase
    "buy ", "price of ", "cost of ", "where to buy", "how much is",
    "purchase ", "order ", "discount ", "sale on ",
    # IMDb/Ratings
    "imdb", "rottentomatoes", "movie rating", "film rating", "netflix",
    "amazon prime video", "hulu ", "disney+", "hbomax",
    # Clearblue/Pregnancy
    "clearblue", "pregnancy test", "ovulation test", "fertility monitor",
    "first response", "predictor test",
    # Call Center/IVR (not marketing)
    "ivr system", "auto dialer", "predictive dialer", "call center software",
    "contact center solution", " telephony ", "voip ",
    # Programming/Technical questions
    "javascript tutorial", "python tutorial", "sql query", "api tutorial",
    "database setup", "how to code", "learn to program",
    "stackoverflow", "github.com", "npm install", "pip install",
    "sudo apt", "brew install",
    # Hospital/Medical RANKINGS (information intent)
    "best hospitals", "top hospitals", "hospital rankings", "hospital rating",
    "medical center ranking", "hospital compare", "hospital review",
    # Medical Education
    "nursing program", "medical school", "residency program", "residency match",
    "board exam", "usmle", "mcat ",
    # Medical CONDITIONS (health info intent)
    "symptoms of ", "treatment for ", "diagnosis ", "medication for ",
    "cure for ", "home remedies for", "how to treat ",
    # Health Insurance
    "health insurance quote", "insurance claim", "insurance policy",
    # News/Media
    "healthcare news", "hospital news", "healthcare merger", "healthcare acquisition",
    "healthcare layoffs", "healthcare ceo ", "industry news",
    # Job Search
    "jobs in healthcare", "healthcare careers", "nursing jobs", "hospital jobs",
    "medical jobs", "physician jobs", "job board",
    # Software Downloads
    "download software", "free software download", "open source",
    "software crack", "serial key", "license key"
)

function Test-KeywordIntent {
    param([string]$keyword)

    $keywordLower = $keyword.ToLower().Trim()

    # Skip empty lines, headers, and comments
    if ([string]::IsNullOrWhiteSpace($keywordLower)) { return "SKIP" }
    if ($keywordLower -match "^(#|-|\d+\.)" ) { return "SKIP" }

    # Check NEGATIVE patterns first (clear intent NOT to hire)
    foreach ($pattern in $negativePatterns) {
        if ($keywordLower -match $pattern) {
            return "NEGATIVE"  # IS a negative keyword
        }
    }

    # Check SERVICE patterns (potential client looking to hire)
    foreach ($pattern in $servicePatterns) {
        if ($keywordLower -match $pattern) {
            return "SERVICE_BUYER"  # NOT a negative keyword
        }
    }

    return "REVIEW"  # Needs human judgment
}

# Read the negative keywords file
$content = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md"

$serviceBuyers = @()
$negatives = @()
$needsReview = @()
$skipped = @()

foreach ($line in $content) {
    $result = Test-KeywordIntent -keyword $line
    switch ($result) {
        "SERVICE_BUYER" { $serviceBuyers += $line }
        "NEGATIVE" { $negatives += $line }
        "REVIEW" { $needsReview += $line }
        "SKIP" { $skipped += $line }
    }
}

Write-Host "=== KEYWORD CATEGORIZATION RESULTS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "SERVICE_BUYER (NOT negative - remove from list): $($serviceBuyers.Count)" -ForegroundColor Green
Write-Host "NEGATIVE (IS a negative keyword - keep): $($negatives.Count)" -ForegroundColor Red
Write-Host "NEEDS REVIEW (uncertain): $($needsReview.Count)" -ForegroundColor Yellow
Write-Host "SKIPPED (headers/comments): $($skipped.Count)" -ForegroundColor Gray
Write-Host ""

# Show samples of each
Write-Host "=== SAMPLE: SERVICE_BUYER (first 30) ===" -ForegroundColor Green
$serviceBuyers | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: NEGATIVE (first 30) ===" -ForegroundColor Red
$negatives | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: NEEDS REVIEW (first 30) ===" -ForegroundColor Yellow
$needsReview | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }

# Save results
$serviceBuyers | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\service_buyer_keywords.txt" -Encoding UTF8
$negatives | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\confirmed_negative_keywords.txt" -Encoding UTF8
$needsReview | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\needs_manual_review.txt" -Encoding UTF8

Write-Host ""
Write-Host "Files exported:" -ForegroundColor Cyan
Write-Host "  - service_buyer_keywords.txt ($($serviceBuyers.Count) keywords to REMOVE)"
Write-Host "  - confirmed_negative_keywords.txt ($($negatives.Count) confirmed negatives)"
Write-Host "  - needs_manual_review.txt ($($needsReview.Count) need human review)"