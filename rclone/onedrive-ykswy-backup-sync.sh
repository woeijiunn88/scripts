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
    for prefix in rclone-archived-onedrive-ykswy-backup-media; do
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
# Sync Archived → OneDrive backup media/Music
# --------------------
echo 'Syncing in progress for Archived (Music backup) ...'
LOGFILE_ARCHIVED="$LOG_DIR/rclone-archived-onedrive-ykswy-archive-media-$(date +%Y%m%d-%H%M%S).log"
rclone sync "/run/media/woeijiunn88/Archived" "onedrive-ykswy-archive-media:Music" \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/rclone-archived-onedrive-ykswy-archive-filter-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level NOTICE \
  --log-file "$LOGFILE_ARCHIVED" \
  --progress

echo 'Execution done.'
