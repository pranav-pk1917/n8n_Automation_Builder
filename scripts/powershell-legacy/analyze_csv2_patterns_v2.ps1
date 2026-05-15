# Analyze negative keyword patterns and find matches in CSV
# Using .NET for proper batch reading

# Read user's negative keywords
$negKeywords = Get-Content "c:\Users\prana\Downloads\-vekeywords.txt"
$negKeywordsLower = $negKeywords | ForEach-Object { $_.ToLower().Trim() }

Write-Host "User found $($negKeywords.Count) negative keywords" -ForegroundColor Cyan

# Extract patterns from negative keywords
$patterns = @()
foreach ($kw in $negKeywordsLower) {
    if ([string]::IsNullOrWhiteSpace($kw)) { continue }
    $words = $kw -split ' '
    if ($words.Count -ge 2) {
        $patterns += $kw
    } else {
        if ($kw.Length -gt 3 -and $kw -notmatch "^(the|and|for|with|in|on|at|to|of)$") {
            $patterns += $kw
        }
    }
}

Write-Host "Extracted $($patterns.Count) patterns" -ForegroundColor Cyan

# Read CSV using .NET for efficiency
$csvPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2.csv"
$reader = [System.IO.File]::OpenRead($csvPath)
$buffer = New-Object byte[] 8192
$foundMatches = @()
$processed = 0

Write-Host ""
Write-Host "Scanning CSV file..." -ForegroundColor Yellow

# Read line by line
$sr = New-Object System.IO.StreamReader($reader)
$lineNum = 0
while (($line = $sr.ReadLine()) -ne $null) {
    $lineNum++
    # Skip header and empty lines
    if ($lineNum -eq 1 -or [string]::IsNullOrWhiteSpace($line)) { continue }

    # Extract keyword (before first comma)
    $keyword = ($line -split ',')[0].Trim()
    if ([string]::IsNullOrWhiteSpace($keyword)) { continue }

    $processed++
    $keywordLower = $keyword.ToLower()

    # Check if any pattern matches
    foreach ($pattern in $patterns) {
        if ($keywordLower -match [regex]::Escape($pattern)) {
            $foundMatches += $keyword
            break
        }
    }

    if ($processed % 10000 -eq 0) {
        Write-Host "  Processed $processed keywords, found $($foundMatches.Count) matches..."
    }
}

$sr.Close()
$reader.Close()

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Green
Write-Host "Total keywords processed: $processed"
Write-Host "Matches found: $($foundMatches.Count)"

# Remove duplicates
$uniqueMatches = $foundMatches | Sort-Object -Unique
Write-Host "Unique matches: $($uniqueMatches.Count)"

# Categorize by pattern type
$categories = @{
    "Instagram Posting Times" = @()
    "Awards/Recognition" = @()
    "Insurance Plans" = @()
    "Agile/Methodology" = @()
    "Digital Transformation" = @()
    "Health Info/Medical" = @()
    "Other" = @()
}

# Categorize each match
foreach ($match in $uniqueMatches) {
    $matchLower = $match.ToLower()
    if ($matchLower -match "best time to post|best time.*post|when.*best time") {
        $categories["Instagram Posting Times"] += $match
    } elseif ($matchLower -match "award|awards|recognition|winning|won") {
        $categories["Awards/Recognition"] += $match
    } elseif ($matchLower -match "plans|medicare|insurance|pbm|health plans") {
        $categories["Insurance Plans"] += $match
    } elseif ($matchLower -match "agile|methodology|sprint|scrum|kanban") {
        $categories["Agile/Methodology"] += $match
    } elseif ($matchLower -match "digital transformation|information technology|it transformation") {
        $categories["Digital Transformation"] += $match
    } elseif ($matchLower -match "health information|medical information|healthcare informatics|lab information") {
        $categories["Health Info/Medical"] += $match
    } else {
        $categories["Other"] += $match
    }
}

Write-Host ""
Write-Host "=== CATEGORIZED MATCHES ===" -ForegroundColor Cyan
foreach ($cat in $categories.Keys) {
    Write-Host "$cat : $($categories[$cat].Count)" -ForegroundColor Yellow
}

# Show samples
Write-Host ""
Write-Host "=== SAMPLE: Instagram Posting Times ===" -ForegroundColor Magenta
$categories["Instagram Posting Times"] | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: Awards/Recognition ===" -ForegroundColor Magenta
$categories["Awards/Recognition"] | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: Insurance Plans ===" -ForegroundColor Magenta
$categories["Insurance Plans"] | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: Other ===" -ForegroundColor Magenta
$categories["Other"] | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

# Save all
$uniqueMatches | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\csv2_negative_matches.txt" -Encoding UTF8

Write-Host ""
Write-Host "Saved to csv2_negative_matches.txt" -ForegroundColor Green