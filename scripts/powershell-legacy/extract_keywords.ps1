# Extract all keywords from negative_keywords.md
$content = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords.md"

$keywords = @()

foreach ($line in $content) {
    $trimmed = $line.Trim()
    # Skip empty lines, headers, comments, bullets
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed -match "^(#|##|\*|- |\*\*|\d+\.)") { continue }
    # Only process lines that look like keywords (letters, numbers, spaces)
    if ($trimmed -match "^[a-zA-Z0-9\s\-\']+$") {
        $keywords += $trimmed.ToLower()
    }
}

# Remove duplicates and sort
$uniqueKeywords = $keywords | Sort-Object -Unique

Write-Host "Extracted $($uniqueKeywords.Count) keywords from current file"

# Export as PowerShell array for verification
$uniqueKeywords | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\extracted_keywords.txt" -Encoding UTF8

Write-Host "Exported to extracted_keywords.txt"