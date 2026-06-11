# ================================
# CONFIGURATION
# ================================
$siteUrl = "https://ykswy-my.sharepoint.com/personal/anime_ykswy_onmicrosoft_com"
$libraryName = "Documents"
$clientId = "801cdef2-a361-4718-ba98-1581c42a01d5"

# ================================
# CONNECT TO SITE
# ================================
try {
    Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId
} catch {
    Write-Host "Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ================================
# GET LIBRARY INFO
# ================================
$list = Get-PnPList -Identity $libraryName

if ($null -eq $list) {
    Write-Error "Library '$libraryName' not found!"
    exit
}

Write-Host "Library '$libraryName' found. Current versioning settings:"
Write-Host "  Major Versions Enabled    : $($list.EnableVersioning)"
Write-Host "  Minor Versions Enabled    : $($list.EnableMinorVersions)"
Write-Host "  Content Approval Required : $($list.EnableModeration)"

# ================================
# TOGGLE VERSIONING (MAJOR ONLY)
# ================================
if ($list.EnableVersioning) {
    # Currently enabled → disable
    Set-PnPList -Identity $libraryName -EnableVersioning $false
    Write-Host "Major versioning has been DISABLED for library '$libraryName'."
} else {
    # Currently disabled → enable
    Set-PnPList -Identity $libraryName -EnableVersioning $true
    Write-Host "Major versioning has been ENABLED for library '$libraryName'."
}
