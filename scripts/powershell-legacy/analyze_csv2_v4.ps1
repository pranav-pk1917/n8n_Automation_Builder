# Analyze CSV2 using proper arrays
# Read user's negative keywords

$negKeywords = Get-Content "c:\Users\prana\Downloads\-vekeywords.txt"
$negPatterns = [System.Collections.ArrayList]::new()
foreach ($kw in $negKeywords) {
    $trimmed = $kw.ToLower().Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        [void]$negPatterns.Add($trimmed)
    }
}

Write-Host "Loaded $($negPatterns.Count) negative patterns" -ForegroundColor Cyan

# Read CSV file
$csvPath = "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\A2 - Compitiotrs_Organic_rankings\keywords_scv2.csv"
Write-Host "Loading CSV..." -ForegroundColor Yellow
$allLines = Get-Content $csvPath

# Extract keywords
$keywords = [System.Collections.ArrayList]::new()
foreach ($line in $allLines) {
    if ($line -match "^[^,]+,") {
        $kw = ($line -split ",")[0].Trim()
        if ($kw -and $kw.Length -gt 1 -and $kw -ne "Keyword") {
            [void]$keywords.Add($kw)
        }
    }
}
Write-Host "Loaded $($keywords.Count) keywords from CSV" -ForegroundColor Cyan

# Find matches
Write-Host "Finding matches..." -ForegroundColor Yellow
$matches = [System.Collections.ArrayList]::new()
$processed = 0
$total = $keywords.Count

foreach ($kw in $keywords) {
    $processed++
    $kwLower = $kw.ToLower()

    foreach ($pattern in $negPatterns) {
        if ($kwLower -match [regex]::Escape($pattern)) {
            [void]$matches.Add($kw)
            break
        }
    }

    if ($processed % 20000 -eq 0) {
        Write-Host "  $processed / $total ... matches so far: $($matches.Count)"
    }
}

Write-Host "Completed! Found $($matches.Count) matches" -ForegroundColor Green

# Remove duplicates
$unique = $matches | Sort-Object -Unique
Write-Host "Unique matches: $($unique.Count)" -ForegroundColor Green

# Categorize
$catInstagram = @()
$catAwards = @()
$catInsurance = @()
$catAgile = @()
$catDT = @()
$catFormat = @()
$catOther = @()

foreach ($m in $unique) {
    $ml = $m.ToLower()
    if ($ml -match "best time.*post|when.*best time") {
        $catInstagram += $m
    } elseif ($ml -match "award|awards|winning") {
        $catAwards += $m
    } elseif ($ml -match "plans|medicare|insurance|pbm|health plan") {
        $catInsurance += $m
    } elseif ($ml -match "agile|methodology|sprint|scrum") {
        $catAgile += $m
    } elseif ($ml -match "digital transformation|information technology") {
        $catDT += $m
    } elseif ($ml -match "format|specification|srs") {
        $catFormat += $m
    } else {
        $catOther += $m
    }
}

Write-Host ""
Write-Host "=== CATEGORIES ===" -ForegroundColor Cyan
Write-Host "Instagram posting times: $($catInstagram.Count)"
Write-Host "Awards/Recognition: $($catAwards.Count)"
Write-Host "Insurance/Health Plans: $($catInsurance.Count)"
Write-Host "Agile/Methodology: $($catAgile.Count)"
Write-Host "Digital Transformation: $($catDT.Count)"
Write-Host "Format/Document: $($catFormat.Count)"
Write-Host "Other: $($catOther.Count)"

Write-Host ""
Write-Host "=== SAMPLE MATCHES ===" -ForegroundColor Yellow
$unique | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }

# Save
$unique | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\csv2_negative_matches.txt" -Encoding UTF8

Write-Host ""
Write-Host "Saved to csv2_negative_matches.txt" -ForegroundColor Green