# scripts

Grab-bag of personal utility scripts: system administration, cloud sync,
media/archive conversion, and dev tooling. Already has a well-maintained root
`README.md` and per-subdirectory READMEs (`amazon/`, `gemini/`, `onedrive/`,
`rclone/`) — **read those for details, this file is just orientation.**

Git repo: `github.com/woeijiunn88/scripts.git`, branch `main`.

## Important: root scripts are symlinked into $HOME

Every root-level script is symlinked from `~/` (e.g. `~/docker-update.sh ->
projects/scripts/docker-update.sh`). Editing the file here changes the live,
symlinked invocation directly — be careful with `rm`/`mv` in this directory since
it affects targets used elsewhere on the system.

## Layout

- Root (~30 scripts): system/environment (`docker-update.sh`, `eno1_restart.sh`,
  `usb-mount.sh`, `shutdown.sh`, `kwallet_unlock.sh`, `kwin_restart.sh`,
  `vmware_autostart.sh`, `sunshine_autostart.sh`, `xfreerdp_login.sh`,
  `pip-upgrade.py`, `migrate_npm.sh`); media/archive (`extract.sh`, `rar_rr5.sh`,
  `epub2cbz.{sh,py}`, `icloud-photos-reprocess.sh`, `kemono-dl.sh`); Melonbooks
  scraping (`dump_melon.py`, `melonbooks_parse.py`, `melonbooks_sample.py`); dev
  tooling (`mcp-index.sh` for codebase-memory-mcp, `start_agent.sh`, `vc.sh`); and
  `cookie_refresh.py` — Playwright-based multi-platform (X/Instagram/Facebook/
  Bilibili/Weibo) cookie keep-alive, reads secrets from `../notify-push/.env`.
- `amazon/` — Playwright-based Amazon diagnostics.
- `gemini/` — Gemini CLI helpers.
- `onedrive/` — PnP PowerShell (SharePoint/OneDrive) automation.
- `rclone/` — cloud sync scripts.

## Deploy

Several scripts run via systemd user timers/services referencing this directory
directly: `rclone-cloud-sync.service` (daily 2AM per README), `onedrive-ykswy-
icloud-photos-sync.service` (hourly), `cookie-refresh.service`.

## Config/secrets

- `~/.config/rclone/rclone.conf` (not tracked in git).
- `.gitignore` excludes `*.lock`, `*.log`, `cookies-*.txt`, `*.env`,
  `__pycache__/`, `*.pyc` — these are expected to exist locally, not committed.
