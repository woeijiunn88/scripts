# onedrive

PowerShell (PnP) admin scripts for managing the `anime_ykswy_onmicrosoft_com` SharePoint/OneDrive site.

## Scripts

| Script | Purpose | Auth |
|---|---|---|
| `onedrive-anime-ykswy-toggle-versioning.ps1` | Toggle major versioning on/off for the Documents library | Interactive browser |
| `onedrive-anime-ykswy-remove-all-versions.ps1` | Delete all file versions across the Documents library | Interactive browser |

## Requirements

- PowerShell 7+ (`pwsh`)
- PnP PowerShell module: `Install-Module PnP.PowerShell`

## Usage

```powershell
# Toggle versioning on/off
pwsh onedrive-anime-ykswy-toggle-versioning.ps1

# Dry-run — preview which files would be processed
pwsh onedrive-anime-ykswy-remove-all-versions.ps1 -WhatIf

# Actually delete all versions
pwsh onedrive-anime-ykswy-remove-all-versions.ps1
```

## Notes

- Both scripts use `-Interactive` auth — a browser window will open on first run, token is cached after that
- `clientId`: `801cdef2-a361-4718-ba98-1581c42a01d5` (app registration in ykswy tenant)
- These are manual-use only — no systemd service runs them
