#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOCKFILE="${SCRIPT_DIR}/$(basename "$0").lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(basename "$0") is already running — exiting"; exit 1; }

LOG_DIR="$HOME/.log/rclone"
mkdir -p "$LOG_DIR"

cleanup() {
    local reason="$1"
    echo "Script exiting due to: $reason"

    find "$LOG_DIR" -type f -name "rclone-*.log" -size 0c -delete

    # update prefix list
    for prefix in work twitter pixiv screenshots-windows screenshots-android screenshots-linux wallpaper dcim; do
        ls -1t "$LOG_DIR"/rclone-${prefix}-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
    done

    rm -f "$LOCKFILE"
    exit 0
}

trap 'cleanup "SIGINT"' SIGINT
trap 'cleanup "SIGTSTP"' SIGTSTP
trap 'cleanup "Exit"' EXIT

# 2FA
echo "Syncing 2FA..."
LOGFILE_2FA="$LOG_DIR/google-drive-davidtay-snow88-2fa-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Documents/2FA google-drive-davidtay-snow88:2FA \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_2FA" \


# Obsidian Vault
echo "Syncing Obsidian Vault..."
LOGFILE_OV="$LOG_DIR/onedrive-personal-vmsnow88-ov-$(date +%Y%m%d-%H%M%S).log"
rclone sync "/home/woeijiunn88/Documents/Obsidian Vault" onedrive-personal-vmsnow88:"Documents/Obsidian Vault" \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_OV" \


# Work
echo "Syncing Work..."
LOGFILE_WORK="$LOG_DIR/onedrive-personal-vmsnow88-work-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Documents/Work onedrive-personal-vmsnow88:Documents/Work \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_WORK"


# Twitter
echo "Syncing Twitter..."
LOGFILE_TWITTER="$LOG_DIR/onedrive-personal-vmsnow88-twitter-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/Twitter onedrive-personal-vmsnow88:Pictures/Twitter \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_TWITTER"


# pixiv
echo "Syncing pixiv..."
LOGFILE_PIXIV="$LOG_DIR/onedrive-personal-vmsnow88-pixiv-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/pixiv onedrive-personal-vmsnow88:Pictures/pixiv \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_PIXIV"


# Flare
echo "Syncing Flare..."
LOGFILE_FLARE="$LOG_DIR/onedrive-personal-vmsnow88-flare-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/Flare onedrive-personal-vmsnow88:Pictures/Flare \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_FLARE"


# Plurk
echo "Syncing Plurk..."
LOGFILE_PLURK="$LOG_DIR/onedrive-personal-vmsnow88-plurk-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/Plurk onedrive-personal-vmsnow88:Pictures/Plurk \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_PLURK"


# Screenshots (Windows)
echo "Syncing Screenshots (Windows)..."
LOGFILE_SS_WIN="$LOG_DIR/onedrive-personal-vmsnow88-screenshots-windows-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Backup/Screenshots/Windows onedrive-personal-vmsnow88:Pictures/Screenshots/Windows \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SS_WIN"


# Screenshots (Android)
echo "Syncing Screenshots (Android)..."
LOGFILE_SS_ANDROID="$LOG_DIR/onedrive-personal-vmsnow88-screenshots-android-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Backup/Screenshots/Android onedrive-personal-vmsnow88:Pictures/Screenshots/Android \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SS_ANDROID"


# Screenshots (Linux)
echo "Syncing Screenshots (Linux)..."
LOGFILE_SS_LINUX="$LOG_DIR/onedrive-personal-vmsnow88-screenshots-linux-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Pictures/Screenshots onedrive-personal-vmsnow88:Pictures/Screenshots/Linux \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SS_LINUX"

# --------------------
# Normalize EXIF date ONLY IF DateTimeOriginal is missing
# --------------------
PHOTO_DIR="/home/woeijiunn88/Pictures/Wallpaper"
echo "Updating EXIF timestamps in $PHOTO_DIR"
exiftool \
  -if 'not $DateTimeOriginal' \
  "-DateTimeOriginal<FileModifyDate" \
  "-CreateDate<FileModifyDate" \
  "-ModifyDate<FileModifyDate" \
  "-FileModifyDate<DateTimeOriginal" \
  -overwrite_original \
  "$PHOTO_DIR"

# Wallpaper (Google Photos)
echo 'Syncing Wallpaper ...'
LOGFILE_WALLPAPER_GP="$LOG_DIR/google-photos-vmsnow88-wallpaper-$(date +%Y%m%d-%H%M%S).log"
rclone sync "/home/woeijiunn88/Pictures/Wallpaper" "google-photos-vmsnow88:album/Wallpaper" \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/google-photos-vmsnow88-wallpaper-list.txt" \
  --checkers 16 --transfers 8 --tpslimit 8 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_WALLPAPER_GP"


# Wallpaper (OneDrive)
echo "Syncing Wallpaper..."
LOGFILE_WALLPAPER_OD="$LOG_DIR/onedrive-personal-vmsnow88-wallpaper-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Pictures/Wallpaper onedrive-personal-vmsnow88:Pictures/Wallpaper \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_WALLPAPER_OD"


# DCIM
echo "Syncing DCIM..."
LOGFILE_DCIM="$LOG_DIR/onedrive-personal-vmsnow88-dcim-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/DCIM onedrive-personal-vmsnow88:DCIM \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_DCIM"


# Sync sda1
echo 'Syncing in progress for sda1 ...'
LOGFILE_SDA1="$LOG_DIR/onedrive-ykswy-sda1-anime-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sda1 onedrive-ykswy-anime: \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-ykswy-sda1-filter-list.txt" \
  --checkers 16 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --onedrive-chunk-size 128M --multi-thread-streams 4 --buffer-size 64M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SDA1"


# Sync sdb1
echo 'Syncing in progress for sdb1 ...'
LOGFILE_SDB1="$LOG_DIR/onedrive-ykswy-sdb1-media-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1 onedrive-ykswy-media: \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-ykswy-sdb1-filter-list.txt" \
  --checkers 16 --transfers 8 --tpslimit 8 --bwlimit 5M \
  --onedrive-chunk-size 128M --multi-thread-streams 4 --buffer-size 64M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SDB1"


echo "Execution done."
