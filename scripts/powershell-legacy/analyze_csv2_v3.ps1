# Analyze CSV2 using simple line-by-line reading
# Read user's negative keywords first

$negKeywords = Get-Content "c:\Users\prana\Downloads\-vekeywords.txt"
$negPatterns = @()
foreach ($kw in $negKeywords) {
    $trimmed = $kw.ToLower().Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        $negPatterns += $trimmed
    }
}

Write-Host "Loaded $($negPatterns.Count) negative patterns from user" -ForegroundColor Cyan

# Read CSV file - get total line count first
$csvPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2.csv"
Write-Host "Getting line count..." -ForegroundColor Yellow
$totalLines = (Get-Content $csvPath).Count
Write-Host "Total lines in CSV: $totalLines" -ForegroundColor Cyan

# Read all keywords from CSV (skip header)
Write-Host "Loading keywords from CSV..." -ForegroundColor Yellow
$allLines = Get-Content $csvPath
$keywords = @()
foreach ($line in $allLines) {
    if ($line -match "^[^,]+,") {
        $kw = ($line -split ",")[0].Trim()
        if ($kw -and $kw.Length -gt 1 -and $kw -ne "Keyword") {
            $keywords += $kw
        }
    }
}
Write-Host "Loaded $($keywords.Count) keywords from CSV" -ForegroundColor Cyan

# Find matches
Write-Host "Finding matches..." -ForegroundColor Yellow
$matches = @()
$processed = 0

foreach ($kw in $keywords) {
    $processed++
    $kwLower = $kw.ToLower()

    foreach ($pattern in $negPatterns) {
        if ($kwLower -match [regex]::Escape($pattern)) {
            $matches += $kw
            break
        }
    }

    if ($processed % 10000 -eq 0) {
        Write-Host "  Processed $processed / $($keywords.Count), found $($matches.Count) matches"
    }
}

# Remove duplicates
$uniqueMatches = $matches | Sort-Object -Unique

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Green
Write-Host "Keywords processed: $($keywords.Count)"
Write-Host "Matches found: $($matches.Count)"
Write-Host "Unique matches: $($uniqueMatches.Count)"

# Categorize
$categories = @{
    "instagram posting times" = @()
    "awards/recognition" = @()
    "insurance/health plans" = @()
    "agile/methodology" = @()
    "digital transformation" = @()
    "format/document" = @()
    "other" = @()
}

foreach ($match in $uniqueMatches) {
    $m = $match.ToLower()
    if ($m -match "best time.*post|when.*best time|best time to post") {
        $categories["instagram posting times"] += $match
    } elseif ($m -match "award|awards|winning|won award") {
        $categories["awards/recognition"] += $match
    } elseif ($m -match "plans|medicare|insurance|pbm|health plan") {
        $categories["insurance/health plans"] += $match
    } elseif ($m -match "agile|methodology|sprint|scrum") {
        $categories["agile/methodology"] += $match
    } elseif ($m -match "digital transformation|information technology|it transformation") {
        $categories["digital transformation"] += $match
    } elseif ($m -match "format|srs document|specification") {
        $categories["format/document"] += $match
    } else {
        $categories["other"] += $match
    }
}

Write-Host ""
Write-Host "=== CATEGORIES ===" -ForegroundColor Cyan
foreach ($cat in $categories.Keys) {
    Write-Host "$cat : $($categories[$cat].Count)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== SAMPLE: Instagram times ($($categories['instagram posting times'].Count)) ==="
$categories["instagram posting times"] | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: Awards ($($categories['awards/recognition'].Count)) ==="
$categories["awards/recognition"] | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE: Other ($($categories['other'].Count)) ==="
$categories["other"] | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }

# Save
$uniqueMatches | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\csv2_negative_matches.txt" -Encoding UTF8

Write-Host ""
Write-Host "Saved $($uniqueMatches.Count) matches to csv2_negative_matches.txt" -ForegroundColor Green