# Combine and format negative keywords properly

# User's existing negative keywords
$existingNegatives = @(
    "2001", "2002", "2003", "2004", "2005", "2006", "2007", "2008", "2009",
    "2010", "2011", "2012", "2013", "2014", "2015", "2016", "2017", "2018",
    "2019", "2020", "2021", "2022", "2023", "2024", "365",
    "affiliate", "affiliates", "affordable", "alternative", "alternatives",
    "apple", "assignment", "assignments", "b2c", "bad", "bads", "bargain",
    "bargains", "bleach", "blogger", "bloggers", "book", "books", "box",
    "boxes", "budget", "budgets", "bug", "bugs", "builder", "builders",
    "calcium", "calculator", "calculators", "calling", "can you", "cancel",
    "cancels", "canva", "capital", "capitals", "career", "careers",
    "certification", "certifications", "chat", "chats", "cheap", "cheapest",
    "clearance", "clearances", "cold call", "cold calls", "college", "colleges",
    "color", "colors", "colour", "colours", "compare", "compares", "con",
    "cons", "contact", "contacts", "cool", "copper", "cost", "costs", "coupon",
    "coupons", "course", "courses", "crack", "cracks", "creator", "creators",
    "css", "customer service", "customer services", "cut", "cutoff", "cutoffs",
    "cuts", "dating", "define", "defines", "definition", "definitions", "degree",
    "degrees", "description", "descriptions", "diploma", "diplomas", "discount",
    "discounts", "diy", "doc", "docs", "documentation", "documentations", "down",
    "drug", "drugs", "dsp", "dsps", "dumb", "earphone", "earphones", "ebook",
    "ebooks", "ehr", "ehrs", "eko", "elementor", "elliott", "email", "emails",
    "error", "errors", "essay", "essays", "example", "examples", "fake",
    "families", "family", "fill a", "fintech", "fiverr", "fix", "fixes", "font",
    "fonts", "forum", "forums", "free", "freelance", "freelancer", "freelancers",
    "freemium", "fresher", "freshers", "funding", "fundings", "game", "games",
    "generator", "generators", "generic", "generics", "germ", "germs", "github",
    "glp", "glps", "godaddy", "good", "goods", "gpt", "gpts", "gratis", "guide",
    "guides", "gun", "guns", "hack", "hacker", "hackers", "hacking", "hacks",
    "hashtag", "hashtags", "help", "helps", "histories", "history", "hobbies",
    "hobby", "home", "homes", "homework", "homeworks", "household", "households",
    "how to", "html", "hvac", "idea", "ideas", "illegal", "image", "images",
    "indiamart", "individual", "individuals", "inexpensive", "infographic",
    "infographics", "inspiration", "inspirations", "installation", "installations",
    "institute", "institutes", "internship", "internships", "interview",
    "interviews", "inventories", "inventory", "iot", "iron", "job", "jobs",
    "jov", "jovs", "kid", "kids", "kill", "kills", "kiss", "kisses", "law",
    "laws", "lawyer", "lawyers", "learn", "learning", "learns", "leave",
    "leaves", "legal", "legit", "letter", "letters", "link", "links", "listing",
    "listings", "login", "logins", "love", "loves", "low cost", "lowest price",
    "lowest prices", "maid", "maids", "make a", "maker", "makers", "mark",
    "marks", "meaning", "meaning of", "meanings", "memorial", "memorials",
    "microsoft", "music", "news", "nih", "not", "note", "notes", "npo", "npos",
    "nulled", "open source", "outage", "outages", "own", "palette", "palettes",
    "payment", "payments", "pdf", "pdfs", "personal", "pirated", "popular",
    "portfolio", "portfolios", "ppt", "ppts", "presentation", "presentations",
    "pro", "promo", "promos", "pros", "provided", "quora", "radio", "radios",
    "readability", "reading", "readings", "recommend", "recommended",
    "recommends", "reddit", "refund", "refunds", "rent", "rental", "rentals",
    "rents", "repair", "repairs", "reset password", "reset passwords",
    "reseller", "resellers", "resume", "resumes", "review", "reviews", "room",
    "rooms", "salaries", "salary", "sample", "samples", "school", "schools",
    "sdk", "sdks", "sex", "shoot", "shooter", "shooters", "shoots", "shortage",
    "shortages", "sign in", "sign ins", "signin", "signins", "signup", "signups",
    "siteground", "small business", "small businesses", "solo", "source code",
    "source codes", "squarespace", "stackoverflow", "stat", "statistic",
    "statistics", "stats", "stock", "stocks", "studies", "study", "subject",
    "subjects", "syllabi", "syllabus", "syllabuses", "tax", "taxes", "tele",
    "teles", "template", "templates", "theses", "thesis", "tip", "tips",
    "torrent", "torrents", "tracking", "trackings", "trading", "training",
    "trainings", "trend", "trending", "trends", "trick", "tricks",
    "troubleshooting", "tutorial", "tutorials", "type", "types", "unbiased",
    "under $", "unfiltered", "universities", "university", "upwork", "vacancies",
    "vacancy", "vacation", "vacations", "versus", "video", "videos", "voip",
    "vs", "warehouse", "warehouses", "watch", "watches", "weapon", "weapons",
    "wearable", "wearables", "webhook", "webhooks", "weebly", "what are some",
    "what is", "widget", "widgets", "wiki", "wikipedia", "wikis", "wix",
    "world report", "world reports", "worst", "write a", "youtube", "best insta", "best instagram", "best youtube", "cerner", "chew", "chews",
    "craig", "ctms", "emr", "emrs", "epic", "epics", "expensive", "fat",
    "fattest", "ford", "fords", "grant", "grants", "graph", "graphs",
    "great place to", "health record", "health records", "hennery", "independent", "independents", "kaiser", "lims", "lis",
    "official website", "official websites", "one touch", "resell", "resells",
    "star", "stars", "who is", "why is", "windows"
)

# Read extracted keywords from file
$extractedContent = Get-Content "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\extracted_keywords.txt"
$extracted = @()
foreach ($line in $extractedContent) {
    $trimmed = $line.Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        $extracted += $trimmed.ToLower()
    }
}

Write-Host "Existing negatives: $($existingNegatives.Count)"
Write-Host "Extracted from file: $($extracted.Count)"

# Combine and deduplicate
$allNegatives = $existingNegatives + $extracted
$uniqueNegatives = $allNegatives | Sort-Object -Unique

Write-Host "Combined unique: $($uniqueNegatives.Count)"

# Build formatted output
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("negative_keywords = [")

$items = @()
foreach ($kw in $uniqueNegatives) {
    $items += "`"$kw`""
}

# Write in rows of 10
for ($i = 0; $i -lt $items.Count; $i++) {
    $comma = if ($i -lt $items.Count - 1) { ", " } else { "" }
    if (($i % 10) -eq 0 -and $i -gt 0) {
        [void]$sb.AppendLine("")
    }
    [void]$sb.Append($items[$i] + $comma)
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("]")

$sb.ToString() | Out-File -FilePath "c:\Users\prana\OneDrive\Documents\Webley Media\SEO\negative_keywords_formatted.js" -Encoding UTF8

Write-Host ""
Write-Host "Total negative keywords: $($uniqueNegatives.Count)"
Write-Host "Saved to negative_keywords_formatted.js"