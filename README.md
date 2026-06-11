# scripts

Personal utility scripts. Each subdirectory has its own README with details.

## Contents

| Path | Description |
|---|---|
| [`rclone/`](rclone/README.md) | OneDrive + Google Photos sync scripts, run by systemd timers |
| [`onedrive/`](onedrive/README.md) | PnP PowerShell admin scripts for SharePoint/OneDrive management |
| [`amazon/`](amazon/README.md) | Playwright diagnostics for Amazon JP account/age-filter checks |
| [`gemini/`](gemini/README.md) | Gemini CLI multi-account management and quota monitoring |
| `dump_melon.py` | Quick Melonbooks product page dump via curl_cffi |
| `melonbooks_parse.py` | Melonbooks product page parser (BeautifulSoup) |
| `migrate_npm.sh` | One-time npm global dir migration to non-sudo setup |

## Notes

- No credentials or tokens are stored here
- Cookie files (`cookies-*.txt`) are excluded via `.gitignore`
- rclone OAuth config lives in `~/.config/rclone/rclone.conf` (not tracked)
