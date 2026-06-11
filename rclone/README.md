# rclone Sync Scripts

Sync scripts and filter lists for OneDrive (ykswy org + personal) and Google Photos.
Credentials and OAuth tokens live in `~/.config/rclone/rclone.conf` — **not tracked in git**.

## Scripts

| Script | Direction | Trigger |
|---|---|---|
| `rclone-cloud-sync.sh` | local → OneDrive/GDrive | Daily 2AM via systemd timer |
| `onedrive-ykswy-icloud-photos-sync.sh` | OneDrive → local | Hourly via systemd timer |
| `onedrive-ykswy-disk-sync.sh` | `/mnt/sdb1` + `/mnt/sda1` → OneDrive | Manual |
| `onedrive-ykswy-backup-sync.sh` | Archived drive → OneDrive | Manual |
| `onedrive-ykswy-software.sh` | Software drive → OneDrive | Manual |
| `google-photos-wallpaper-sync.sh` | local → Google Photos | Manual |

## Sync flow

```
iPhone → iCloud → OneDrive ykswy (Camera Roll)
  └─ [hourly] onedrive-ykswy-icloud-photos-sync.sh
       └─ /mnt/sdb1/DCIM/Apple      (Camera photos/videos)
       └─ /mnt/sdb1/Backup/Apple/   (Screenshots, Screen Recordings, Others)
            └─ [daily 2AM] rclone-cloud-sync.sh
                 └─ OneDrive personal (DCIM, Pictures, Documents)
```

## Filter lists (`list/`)

| File | Used by |
|---|---|
| `onedrive-personal-vmsnow88-list.txt` | `rclone-cloud-sync.sh` — personal OneDrive jobs |
| `onedrive-ykswy-sda1-filter-list.txt` | `rclone-cloud-sync.sh`, `onedrive-ykswy-disk-sync.sh` — sda1 anime |
| `onedrive-ykswy-sdb1-filter-list.txt` | `rclone-cloud-sync.sh`, `onedrive-ykswy-disk-sync.sh` — sdb1 media |
| `rclone-archived-onedrive-ykswy-archive-filter-list.txt` | `onedrive-ykswy-backup-sync.sh`, `onedrive-ykswy-software.sh` |
| `google-photos-vmsnow88-wallpaper-list.txt` | `rclone-cloud-sync.sh` — Google Photos wallpaper job |

## Runtime files (not in git)

| File | Purpose |
|---|---|
| `~/.config/rclone/rclone.conf` | rclone remotes + OAuth tokens |
| `~/.config/rclone/onedrive-ykswy-icloud-photos-sync-last-run.txt` | iCloud sync state (last mtime epoch) |
| `~/.log/rclone/` | Per-run log files |

## Systemd units

```
~/.config/systemd/user/rclone-cloud-sync.service + .timer
~/.config/systemd/user/onedrive-ykswy-icloud-photos-sync.service + .timer
```

## Setup on new machine

1. Install rclone and authenticate remotes: `rclone config`
2. Clone this repo to `~/projects/scripts/rclone/`
3. Ensure log dir exists: `mkdir -p ~/.log/rclone`
4. Copy systemd units to `~/.config/systemd/user/` and reload:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now rclone-cloud-sync.timer
   systemctl --user enable --now onedrive-ykswy-icloud-photos-sync.timer
   ```
