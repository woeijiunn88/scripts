# ================================
# CONFIGURATION
# ================================
param([switch]$WhatIf)

$siteUrl = "https://ykswy-my.sharepoint.com/personal/anime_ykswy_onmicrosoft_com"
$clientId = "801cdef2-a361-4718-ba98-1581c42a01d5"
$libraryName = "Documents"   # Change to your library name

# Counters
$filesProcessed = 0
$filesLeft = 0

# ================================
# CONNECT TO SHAREPOINT SITE
# ================================
try {
    Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId
} catch {
    Write-Host "Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ================================
# GET ALL FILE ITEMS IN THE LIBRARY
# ================================
$items = Get-PnPListItem -List $libraryName |
         Where-Object { $_.FileSystemObjectType -eq "File" }

# ================================
# DELETE ALL VERSIONS FOR EACH FILE
# ================================
foreach ($item in $items) {
    $fileRef = $item.FieldValues["FileRef"]
    Write-Host "Processing file: $fileRef"

    if ($WhatIf) {
        Write-Host " → [DRY RUN] Would delete all versions of $fileRef" -ForegroundColor Cyan
        $filesProcessed++
    } else {
        try {
            Remove-PnPFileVersion -Url $fileRef -All -Force
            Write-Host " → Deleted all versions of $fileRef" -ForegroundColor Green
            $filesProcessed++
        }
        catch {
            Write-Warning "Failed to delete versions for $fileRef. Error: $_"
            $filesLeft++
        }
    }
}

# ================================
# SUMMARY
# ================================
Write-Host "==============================="
if ($WhatIf) { Write-Host "[DRY RUN] Summary:" } else { Write-Host "Summary:" }
Write-Host "Files successfully processed: $filesProcessed" -ForegroundColor Green
Write-Host "Files left (failed): $filesLeft" -ForegroundColor Yellow
Write-Host "Total files: $($filesProcessed + $filesLeft)"
Write-Host "==============================="
