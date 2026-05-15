# Combine existing negatives with new matches and create filtered CSV

# Load existing negative keywords
$negPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md"
$existingContent = Get-Content $negPath

# Extract existing keywords from the array format
$existingNegatives = @()
foreach ($line in $existingContent) {
    if ($line -match '"([^"]+)"') {
        $existingNegatives += $matches[1].ToLower()
    }
}
Write-Host "Existing negatives: $($existingNegatives.Count)" -ForegroundColor Cyan

# Load new matches from CSV analysis
$newMatches = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\csv2_negative_matches.txt"
$newNegatives = @()
foreach ($m in $newMatches) {
    $trimmed = $m.ToLower().Trim()
    if ($trimmed.Length -gt 0) {
        $newNegatives += $trimmed
    }
}
Write-Host "New matches from CSV: $($newNegatives.Count)" -ForegroundColor Cyan

# Combine
$allNegatives = $existingNegatives + $newNegatives
$uniqueAll = $allNegatives | Sort-Object -Unique
Write-Host "Combined unique: $($uniqueAll.Count)" -ForegroundColor Green

# Create new formatted array
$output = "negative_keywords = [`n"
$items = @()
foreach ($kw in $uniqueAll) {
    $items += "`"$kw`""
}

# Group in rows of 10
$maxPerLine = 10
for ($i = 0; $i -lt $items.Count; $i++) {
    $comma = if ($i -lt $items.Count - 1) { ", " } else { "" }
    if (($i % $maxPerLine) -eq 0 -and $i -gt 0) {
        $output += "`n"
    }
    $output += $items[$i] + $comma
}

$output += "`n]"

# Save updated negative_keywords.md
$output | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md" -Encoding UTF8
Write-Host ""
Write-Host "Updated negative_keywords.md with $($uniqueAll.Count) total keywords" -ForegroundColor Green

# Now filter the CSV - remove keywords that match negatives
Write-Host ""
Write-Host "Creating filtered CSV without negative keywords..." -ForegroundColor Yellow

$csvPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2.csv"
$filteredPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2_filtered.csv"

$csvLines = Get-Content $csvPath
$filteredLines = @()
$removedCount = 0
$keptCount = 0

foreach ($line in $csvLines) {
    if ($line -match "^Keyword,") {
        $filteredLines += $line
        continue
    }

    if ($line -match "^[^,]+,") {
        $kw = ($line.Split(","))[0].Trim()
        $kwLower = $kw.ToLower()
        $isNegative = $false

        foreach ($neg in $uniqueAll) {
            if ($kwLower -match [regex]::Escape($neg)) {
                $isNegative = $true
                break
            }
        }

        if ($isNegative) {
            $removedCount++
        } else {
            $filteredLines += $line
            $keptCount++
        }
    }
}

# Save filtered CSV
$filteredLines | Out-File -FilePath $filteredPath -Encoding UTF8

Write-Host ""
Write-Host "=== FILTERED CSV RESULTS ===" -ForegroundColor Green
Write-Host "Keywords removed: $removedCount"
Write-Host "Keywords kept: $keptCount"
Write-Host "Saved to keywords_scv2_filtered.csv" -ForegroundColor Green