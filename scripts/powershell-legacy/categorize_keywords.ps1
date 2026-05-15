# Keyword Categorization Tool for Negative Keywords
# Purpose: Identify keywords where user intent is NOT to hire marketing services

# Services Webley Media Provides (keywords containing these = potential clients)
$servicePatterns = @(
    "seo service",
    "web development",
    "app development",
    "marketing service",
    "marketing agency",
    "digital marketing",
    "social media marketing",
    "performance marketing",
    "ppc service",
    "ppc agency",
    "content marketing",
    "marketing consultant",
    "marketing company",
    "design agency",
    "ux agency",
    "ui design",
    "web design",
    "website design",
    "mobile app",
    "crm service",
    "marketing automation",
    "ai chatbot",
    "marketing platform",
    "advertising agency",
    "lead generation",
    "marketing software",
    "email marketing",
    "video marketing",
    "ecommerce development",
    "shopify development",
    "wordpress development",
    "seo company",
    "seo agency",
    "local seo",
    "seo specialist",
    "marketing firm",
    "creative agency",
    "branding agency",
    "agency for",
    "services for"
)

# Patterns indicating NEGATIVE keywords (user intent is NOT to hire marketing)
$negativePatterns = @(
    # Consumer products/purchases
    "buy ",
    "price of ",
    "cost of ",
    "where to buy",
    "how much is",
    "purchase ",
    "order ",
    # Movie/entertainment
    "imdb",
    "rottentomatoes",
    "movie rating",
    "film rating",
    "netflix",
    "hulu",
    "disney+",
    "amazon prime",
    # Pregnancy/fertility products
    "clearblue",
    "pregnancy test",
    "ovulation test",
    "fertility monitor",
    # Call center/IVR
    "ivr system",
    "auto dialer",
    "predictive dialer",
    "call center software",
    "contact center",
    # Programming/development questions
    "how to code",
    "javascript tutorial",
    "python for ",
    "sql query",
    "api tutorial",
    "database setup",
    "install ",
    "npm ",
    "git ",
    "python script",
    # Hospital/medical rankings (job/career/information)
    "best hospitals",
    "top hospitals",
    "hospital rankings",
    "medical center ranking",
    "nursing program",
    "medical school ranking",
    "residency program",
    "hospital to work for",
    # Medical conditions/info
    "symptoms of ",
    "treatment for ",
    "diagnosis ",
    "medication for",
    "cure for",
    # News/industry info
    "healthcare news",
    "hospital news",
    "healthcare merger",
    "healthcare acquisition",
    "industry news",
    # Job search
    "jobs in healthcare",
    "healthcare careers",
    "nursing jobs",
    "hospital jobs",
    "medical jobs",
    # Software download/install
    "download ",
    "free software",
    "open source",
    "github",
    "stackoverflow"
)

function Test-KeywordIntent {
    param([string]$keyword)

    $keywordLower = $keyword.ToLower()

    # Check if keyword contains service patterns (potential client)
    foreach ($pattern in $servicePatterns) {
        if ($keywordLower -match $pattern) {
            return "SERVICE_BUYER"  # NOT a negative keyword
        }
    }

    # Check if keyword contains negative patterns
    foreach ($pattern in $negativePatterns) {
        if ($keywordLower -match $pattern) {
            return "NEGATIVE"  # IS a negative keyword
        }
    }

    return "REVIEW"  # Needs manual review
}

# Read the negative keywords file
$content = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md"

$serviceBuyers = @()
$negatives = @()
$needsReview = @()

foreach ($line in $content) {
    if ($line -match "^\w") {
        $result = Test-KeywordIntent -keyword $line.Trim()
        switch ($result) {
            "SERVICE_BUYER" { $serviceBuyers += $line }
            "NEGATIVE" { $negatives += $line }
            "REVIEW" { $needsReview += $line }
        }
    }
}

Write-Host "=== CATEGORIZATION RESULTS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "SERVICE_BUYER (NOT negative keywords - potential clients): $($serviceBuyers.Count)" -ForegroundColor Green
Write-Host "NEGATIVE (IS a negative keyword): $($negatives.Count)" -ForegroundColor Red
Write-Host "NEEDS REVIEW (uncertain intent): $($needsReview.Count)" -ForegroundColor Yellow
Write-Host ""

# Show samples
Write-Host "=== SAMPLE SERVICE_BUYER (first 20) ===" -ForegroundColor Green
$serviceBuyers | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE NEEDS REVIEW (first 20) ===" -ForegroundColor Yellow
$needsReview | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

# Export results
$serviceBuyers | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\potential_clients.txt" -Encoding UTF8
$needsReview | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\needs_review.txt" -Encoding UTF8

Write-Host ""
Write-Host "Files exported:" -ForegroundColor Cyan
Write-Host "  - potential_clients.txt (keywords to REMOVE from negative list)"
Write-Host "  - needs_review.txt (keywords needing manual review)"