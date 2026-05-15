# Analyze negative keyword patterns and find matches in CSV

# Read user's negative keywords
$negKeywords = Get-Content "c:\Users\prana\Downloads\-vekeywords.txt"
$negKeywordsLower = $negKeywords | ForEach-Object { $_.ToLower().Trim() }

Write-Host "User found $($negKeywords.Count) negative keywords" -ForegroundColor Cyan

# Extract patterns/phrases from negative keywords
$patterns = @()

foreach ($kw in $negKeywordsLower) {
    # Skip empty lines
    if ([string]::IsNullOrWhiteSpace($kw)) { continue }

    # Split into words and check meaningful patterns
    $words = $kw -split ' '
    if ($words.Count -ge 2) {
        # Multi-word patterns (phrases)
        $patterns += $kw
    } else {
        # Single significant words
        if ($kw.Length -gt 3 -and $kw -notmatch "^(the|and|for|with|in|on|at|to|of)$") {
            $patterns += $kw
        }
    }
}

Write-Host "Extracted $($patterns.Count) patterns/phrases" -ForegroundColor Cyan

# Read the CSV file in batches
$csvPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2.csv"
$batchSize = 10000
$skip = 0
$foundMatches = @()
$processed = 0

Write-Host ""
Write-Host "Analyzing CSV file in batches..." -ForegroundColor Yellow

while ($true) {
    $batch = Get-Content $csvPath -TotalCount ($batchSize + 1) -Skip $skip | Select-Object -First $batchSize
    if ($batch.Count -eq 0) { break }

    $keywordLines = $batch | Where-Object { $_ -match "^[^,]+$" } | ForEach-Object { $_.Trim() }

    foreach ($line in $keywordLines) {
        $processed++
        $lineLower = $line.ToLower()

        # Check if any pattern matches
        foreach ($pattern in $patterns) {
            if ($lineLower -match [regex]::Escape($pattern)) {
                $foundMatches += $line
                break  # Move to next keyword once matched
            }
        }
    }

    Write-Host "  Processed $processed keywords, found $($foundMatches.Count) matches so far..."
    $skip += $batchSize
    if ($batch.Count -lt $batchSize) { break }
}

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Green
Write-Host "Total keywords processed: $processed"
Write-Host "Matches found: $($foundMatches.Count)"
Write-Host ""

# Remove duplicates and sort
$uniqueMatches = $foundMatches | Sort-Object -Unique

Write-Host "Unique matches: $($uniqueMatches.Count)"
Write-Host ""

# Categorize matches by pattern type
Write-Host "=== SAMPLE MATCHES (first 50) ===" -ForegroundColor Yellow
$uniqueMatches | Select-Object -First 50 | ForEach-Object { Write-Host "  $_" }

# Save all matches
$uniqueMatches | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\csv2_negative_matches.txt" -Encoding UTF8

Write-Host ""
Write-Host "Saved to csv2_negative_matches.txt" -ForegroundColor Green