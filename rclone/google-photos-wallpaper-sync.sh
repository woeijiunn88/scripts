#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOCKFILE="${SCRIPT_DIR}/$(basename "$0").lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(basename "$0") is already running — exiting"; exit 1; }

# Create log directory
LOG_DIR="$HOME/.log/rclone"
mkdir -p "$LOG_DIR"

# Cleanup function
cleanup() {
    local reason="$1"
    echo "Script exiting due to: $reason"

    # Remove any 0B log files
    find "$LOG_DIR" -type f -name "rclone-*.log" -size 0c -delete

    # Keep only latest 5 logs for each sync job
    for prefix in rclone-google-photos-wallpaper; do
        ls -1t "$LOG_DIR"/${prefix}-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
    done

    rm -f "$LOCKFILE"
    exit 0
}

# Handle signals
trap 'cleanup "Ctrl+C (SIGINT)"' SIGINT
trap 'cleanup "Ctrl+Z (SIGTSTP)"' SIGTSTP
trap 'cleanup "Normal exit or other signal"' EXIT

# --------------------
# Normalize EXIF date ONLY IF DateTimeOriginal is missing
# --------------------
PHOTO_DIR="/home/woeijiunn88/Pictures/Wallpaper"

exiftool \
  -if 'not $DateTimeOriginal' \
  "-DateTimeOriginal<FileModifyDate" \
  "-CreateDate<FileModifyDate" \
  "-ModifyDate<FileModifyDate" \
  "-FileModifyDate<DateTimeOriginal" \
  -overwrite_original \
  "$PHOTO_DIR"

# --------------------
# Sync Wallpaper
# --------------------
echo 'Syncing in progress for Wallpaper ...'
LOGFILE_WALLPAPER="$LOG_DIR/rclone-google-photos-wallpaper-$(date +%Y%m%d-%H%M%S).log"
rclone sync "/home/woeijiunn88/Pictures/Wallpaper" "google-photos-vmsnow88:album/Wallpaper" \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/rclone-google-photos-wallpaper-list.txt" \
  --checkers 16 --transfers 8 --tpslimit 8 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level NOTICE \
  --log-file "$LOGFILE_WALLPAPER" \
  --progress

echo 'Execution done.'
