# scripts

Personal utility scripts. Each subdirectory has its own README with details.

## Contents

### Subdirectories

| Path | Description |
|---|---|
| [`rclone/`](rclone/README.md) | OneDrive + Google Photos sync scripts, run by systemd timers |
| [`onedrive/`](onedrive/README.md) | PnP PowerShell admin scripts for SharePoint/OneDrive management |
| [`amazon/`](amazon/README.md) | Playwright diagnostics for Amazon JP account/age-filter checks |
| [`gemini/`](gemini/README.md) | Gemini CLI multi-account management and quota monitoring |

### System / environment

| Script | Description |
|---|---|
| `docker-update.sh` | Stop, pull, and restart all Docker Compose services |
| `eno1_restart.sh` | Restart a network interface (default: eno1) |
| `usb-mount.sh` | Mount and unmount USB drives under /mnt/usb/<label> |
| `shutdown.sh` | Immediate system shutdown |
| `kwallet_unlock.sh` | Unlock KDE Wallet via qdbus |
| `kwin_restart.sh` | Restart KWin/Plasma shell |
| `vmware_autostart.sh` | Autostart VMware VMs on KDE login |
| `sunshine_autostart.sh` | Autostart Sunshine game streaming on KDE login |
| `xfreerdp_login.sh` | RDP login helper |
| `pip-upgrade.py` | Safely upgrade all outdated pip packages |
| `migrate_npm.sh` | One-time npm global dir migration to non-sudo setup |

### Media / archive utilities

| Script | Description |
|---|---|
| `extract.sh` | Universal archive extractor (zip, tar, rar, 7z, etc.) |
| `rar_rr5.sh` | RAR archiver with 5% recovery record |
| `epub2cbz.sh` | Batch convert .epub files to .cbz |
| `epub2cbz.py` | Convert a single EPUB file to CBZ format |
| `manictime-png-to-jpg-90.sh` | Convert PNG screenshots to JPG at 90% quality |
| `icloud-photos-reprocess.sh` | Reprocess iCloud photo downloads |
| `kemono-dl.sh` | Kemono.party downloader wrapper |

### Melonbooks

| Script | Description |
|---|---|
| `dump_melon.py` | Quick Melonbooks product page dump via curl_cffi |
| `melonbooks_parse.py` | Melonbooks product page parser (BeautifulSoup) |
| `melonbooks_sample.py` | Melonbooks sample image fetcher |

### Development / tooling

| Script | Description |
|---|---|
| `mcp-index.sh` | Manage codebase-memory-mcp indexes |
| `start_agent.sh` | Start AI agent script |
| `vc.sh` | VeraCrypt volume mount/unmount manager |
| `fix_bash.py` | Patch bash scripts (yt-monitor-lib.sh path fixer) |
| `fix_kb.py` | Patch Python files (yt-monitor-bot.py path fixer) |
| `refresh_ui.py` | UI refresh utility |
| `revert.py` | Revert bash/script changes |
| `mutagen_cover_test.py` | Test FLAC cover detection via mutagen |
| `test_cancel.sh` | Test script cancellation/signal handling |

## Notes

- No credentials or tokens are stored here
- Cookie files (`cookies-*.txt`) are excluded via `.gitignore`
- rclone OAuth config lives in `~/.config/rclone/rclone.conf` (not tracked)
- All root-level scripts are symlinked to `~/` for convenience
