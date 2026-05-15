# Simple approach - use Select-String for pattern matching
$csvPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2.csv"
$negPath = "c:\Users\prana\Downloads\-vekeywords.txt"

Write-Host "Loading negative keywords from user..." -ForegroundColor Cyan
$negLines = Get-Content $negPath
$negPatterns = @()
foreach ($line in $negLines) {
    $trimmed = $line.ToLower().Trim()
    if ($trimmed.Length -gt 2) {
        $negPatterns += $trimmed
    }
}
Write-Host "Loaded $($negPatterns.Count) patterns" -ForegroundColor Cyan

Write-Host "Loading CSV keywords..." -ForegroundColor Cyan
$csvLines = Get-Content $csvPath
$keywords = @()
foreach ($line in $csvLines) {
    if ($line -match "^[^,]+,") {
        $kw = ($line.Split(","))[0].Trim()
        if ($kw.Length -gt 2 -and $kw -ne "Keyword") {
            $keywords += $kw
        }
    }
}
Write-Host "Loaded $($keywords.Count) keywords from CSV" -ForegroundColor Cyan

Write-Host ""
Write-Host "Finding matches using Select-String..." -ForegroundColor Yellow

$allMatches = @()
$count = 0
foreach ($kw in $keywords) {
    $count++
    $kwLower = $kw.ToLower()
    foreach ($pat in $negPatterns) {
        if ($kwLower -match $pat) {
            $allMatches += $kw
            break
        }
    }
    if ($count % 20000 -eq 0) {
        Write-Host "  Processed $count keywords..."
    }
}

$uniqueMatches = $allMatches | Sort-Object -Unique
Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Green
Write-Host "Matches found: $($allMatches.Count)"
Write-Host "Unique matches: $($uniqueMatches.Count)"

# Categorize
$instagram = $uniqueMatches | Where-Object { $_.ToLower() -match "best time.*post" }
$awards = $uniqueMatches | Where-Object { $_.ToLower() -match "award" }
$insurance = $uniqueMatches | Where-Object { $_.ToLower() -match "plans|medicare|insurance|pbm" }
$agile = $uniqueMatches | Where-Object { $_.ToLower() -match "agile|methodology" }
$dt = $uniqueMatches | Where-Object { $_.ToLower() -match "digital transformation" }
$other = $uniqueMatches | Where-Object {
    $_.ToLower() -notmatch "best time.*post|award|plans|medicare|insurance|pbm|agile|methodology|digital transformation"
}

Write-Host ""
Write-Host "=== CATEGORIES ===" -ForegroundColor Cyan
Write-Host "Instagram posting times: $($instagram.Count)"
Write-Host "Awards: $($awards.Count)"
Write-Host "Insurance/Health Plans: $($insurance.Count)"
Write-Host "Agile/Methodology: $($agile.Count)"
Write-Host "Digital Transformation: $($dt.Count)"
Write-Host "Other: $($other.Count)"

Write-Host ""
Write-Host "=== SAMPLE INSTAGRAM MATCHES ===" -ForegroundColor Magenta
$instagram | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== SAMPLE OTHER ===" -ForegroundColor Magenta
$other | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

# Save
$uniqueMatches | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\csv2_negative_matches.txt" -Encoding UTF8
Write-Host ""
Write-Host "Saved to csv2_negative_matches.txt" -ForegroundColor Green