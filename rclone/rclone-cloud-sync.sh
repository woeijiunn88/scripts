#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOCKFILE="${SCRIPT_DIR}/$(basename "$0").lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(basename "$0") is already running — exiting"; exit 1; }

LOG_DIR="$HOME/.log/rclone"
mkdir -p "$LOG_DIR"

GOTIFY_URL="http://localhost:8090"
GOTIFY_TOKEN_FILE="$HOME/.config/rclone/gotify-rclone-token"
GOTIFY_TOKEN="$(cat "$GOTIFY_TOKEN_FILE" 2>/dev/null)"
FAILED_JOBS=()
FAILED_LOGS=()
TOTAL_JOBS=15
JOBS_RUN=0
START_TIME=$(date +%s)

_gotify() {
    local title="$1" msg="$2" priority="${3:-7}"
    [[ -z "$GOTIFY_TOKEN" ]] && return
    local payload
    payload=$(jq -n --arg t "$title" --arg m "$msg" --argjson p "$priority" \
        '{title:$t,message:$m,priority:$p}')
    curl -s -X POST "$GOTIFY_URL/message" \
        -H "X-Gotify-Key: $GOTIFY_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        > /dev/null
}

_duration() {
    local secs=$(( $(date +%s) - START_TIME ))
    local h=$(( secs / 3600 )) m=$(( (secs % 3600) / 60 ))
    [[ $h -gt 0 ]] && echo "${h}h ${m}m" || echo "${m}m"
}

_job_cause() {
    local logfile="$1"
    [[ -z "$logfile" || ! -f "$logfile" ]] && echo "unknown error" && return
    local cause
    cause=$(grep "NOTICE:.*Failed to sync" "$logfile" | tail -1 | sed 's/.*NOTICE: //')
    [[ -z "$cause" ]] && cause=$(grep " ERROR " "$logfile" | tail -1 | sed 's/.*ERROR : //')
    [[ -z "$cause" ]] && cause="unknown error"
    echo "${cause:0:120}"
}

cleanup() {
    local reason="$1"
    echo "Script exiting due to: $reason"

    find "$LOG_DIR" -type f -name "*.log" -size 0c -delete

    for prefix in \
        google-drive-davidtay-snow88-2fa \
        onedrive-personal-vmsnow88-ov \
        onedrive-personal-vmsnow88-work \
        onedrive-personal-vmsnow88-twitter \
        onedrive-personal-vmsnow88-pixiv \
        onedrive-personal-vmsnow88-flare \
        onedrive-personal-vmsnow88-plurk \
        onedrive-personal-vmsnow88-screenshots-windows \
        onedrive-personal-vmsnow88-screenshots-android \
        onedrive-personal-vmsnow88-screenshots-linux \
        google-photos-vmsnow88-wallpaper \
        onedrive-personal-vmsnow88-wallpaper \
        onedrive-personal-vmsnow88-dcim \
        onedrive-ykswy-sda1-anime \
        onedrive-ykswy-sdb1-media; do
        ls -1t "$LOG_DIR"/${prefix}-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
    done

    local dur
    dur="$(_duration)"
    local failed=${#FAILED_JOBS[@]}

    _build_detail() {
        local i
        for i in "${!FAILED_JOBS[@]}"; do
            local cause
            cause="$(_job_cause "${FAILED_LOGS[$i]}")"
            printf '• %s: %s\n' "${FAILED_JOBS[$i]}" "$cause"
        done
    }

    if [[ "$reason" == "SIGINT" || "$reason" == "SIGTSTP" ]]; then
        local msg="Interrupted after ${JOBS_RUN}/${TOTAL_JOBS} jobs  •  ${dur}"
        [[ $failed -gt 0 ]] && msg+=$'\n'"$(_build_detail)"
        _gotify "rclone sync aborted" "$msg" 8
        echo "Notified Gotify: aborted"
    elif [[ $failed -gt 0 ]]; then
        local detail
        detail="$(_build_detail)"
        _gotify "rclone sync failed" "${failed}/${TOTAL_JOBS} jobs failed  •  ${dur}"$'\n'"${detail}" 8
        echo "Notified Gotify: failed jobs — ${FAILED_JOBS[*]}"
    else
        _gotify "rclone sync done" "All ${TOTAL_JOBS} jobs OK  •  ${dur}" 3
        echo "Notified Gotify: all jobs OK"
    fi

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
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_2FA" || { FAILED_JOBS+=("2fa"); FAILED_LOGS+=("$LOGFILE_2FA"); }
JOBS_RUN+=1


# Obsidian Vault
echo "Syncing Obsidian Vault..."
LOGFILE_OV="$LOG_DIR/onedrive-personal-vmsnow88-ov-$(date +%Y%m%d-%H%M%S).log"
rclone sync "/home/woeijiunn88/Documents/Obsidian Vault" onedrive-personal-vmsnow88:"Documents/Obsidian Vault" \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_OV" || { FAILED_JOBS+=("obsidian"); FAILED_LOGS+=("$LOGFILE_OV"); }
JOBS_RUN+=1


# Work
echo "Syncing Work..."
LOGFILE_WORK="$LOG_DIR/onedrive-personal-vmsnow88-work-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Documents/Work onedrive-personal-vmsnow88:Documents/Work \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_WORK" || { FAILED_JOBS+=("work"); FAILED_LOGS+=("$LOGFILE_WORK"); }
JOBS_RUN+=1


# X (Twitter)
echo "Syncing X (Twitter)..."
LOGFILE_TWITTER="$LOG_DIR/onedrive-personal-vmsnow88-twitter-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/Twitter onedrive-personal-vmsnow88:Pictures/Twitter \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_TWITTER" || { FAILED_JOBS+=("twitter"); FAILED_LOGS+=("$LOGFILE_TWITTER"); }
JOBS_RUN+=1


# pixiv
echo "Syncing pixiv..."
LOGFILE_PIXIV="$LOG_DIR/onedrive-personal-vmsnow88-pixiv-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/pixiv onedrive-personal-vmsnow88:Pictures/pixiv \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_PIXIV" || { FAILED_JOBS+=("pixiv"); FAILED_LOGS+=("$LOGFILE_PIXIV"); }
JOBS_RUN+=1


# Flare
echo "Syncing Flare..."
LOGFILE_FLARE="$LOG_DIR/onedrive-personal-vmsnow88-flare-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/Flare onedrive-personal-vmsnow88:Pictures/Flare \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_FLARE" || { FAILED_JOBS+=("flare"); FAILED_LOGS+=("$LOGFILE_FLARE"); }
JOBS_RUN+=1


# Plurk
echo "Syncing Plurk..."
LOGFILE_PLURK="$LOG_DIR/onedrive-personal-vmsnow88-plurk-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Pictures/Plurk onedrive-personal-vmsnow88:Pictures/Plurk \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_PLURK" || { FAILED_JOBS+=("plurk"); FAILED_LOGS+=("$LOGFILE_PLURK"); }
JOBS_RUN+=1


# Screenshots (Windows)
echo "Syncing Screenshots (Windows)..."
LOGFILE_SS_WIN="$LOG_DIR/onedrive-personal-vmsnow88-screenshots-windows-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Backup/Screenshots/Windows onedrive-personal-vmsnow88:Pictures/Screenshots/Windows \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SS_WIN" || { FAILED_JOBS+=("screenshots-windows"); FAILED_LOGS+=("$LOGFILE_SS_WIN"); }
JOBS_RUN+=1


# Screenshots (Android)
echo "Syncing Screenshots (Android)..."
LOGFILE_SS_ANDROID="$LOG_DIR/onedrive-personal-vmsnow88-screenshots-android-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/Backup/Screenshots/Android onedrive-personal-vmsnow88:Pictures/Screenshots/Android \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SS_ANDROID" || { FAILED_JOBS+=("screenshots-android"); FAILED_LOGS+=("$LOGFILE_SS_ANDROID"); }
JOBS_RUN+=1


# Screenshots (Linux)
echo "Syncing Screenshots (Linux)..."
LOGFILE_SS_LINUX="$LOG_DIR/onedrive-personal-vmsnow88-screenshots-linux-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Pictures/Screenshots onedrive-personal-vmsnow88:Pictures/Screenshots/Linux \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_SS_LINUX" || { FAILED_JOBS+=("screenshots-linux"); FAILED_LOGS+=("$LOGFILE_SS_LINUX"); }
JOBS_RUN+=1

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
  --log-file "$LOGFILE_WALLPAPER_GP" || { FAILED_JOBS+=("wallpaper-googlephotos"); FAILED_LOGS+=("$LOGFILE_WALLPAPER_GP"); }
JOBS_RUN+=1


# Wallpaper (OneDrive)
echo "Syncing Wallpaper..."
LOGFILE_WALLPAPER_OD="$LOG_DIR/onedrive-personal-vmsnow88-wallpaper-$(date +%Y%m%d-%H%M%S).log"
rclone sync /home/woeijiunn88/Pictures/Wallpaper onedrive-personal-vmsnow88:Pictures/Wallpaper \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_WALLPAPER_OD" || { FAILED_JOBS+=("wallpaper-onedrive"); FAILED_LOGS+=("$LOGFILE_WALLPAPER_OD"); }
JOBS_RUN+=1


# DCIM
echo "Syncing DCIM..."
LOGFILE_DCIM="$LOG_DIR/onedrive-personal-vmsnow88-dcim-$(date +%Y%m%d-%H%M%S).log"
rclone sync /mnt/sdb1/DCIM onedrive-personal-vmsnow88:DCIM \
  --track-renames \
  --filter-from "$HOME/projects/scripts/rclone/list/onedrive-personal-vmsnow88-list.txt" \
  --checkers 8 --transfers 4 --tpslimit 4 --bwlimit 5M \
  --retries 10 --low-level-retries 20 --timeout 10s --retries-sleep 5s \
  --log-level INFO \
  --log-file "$LOGFILE_DCIM" || { FAILED_JOBS+=("dcim"); FAILED_LOGS+=("$LOGFILE_DCIM"); }
JOBS_RUN+=1


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
  --log-file "$LOGFILE_SDA1" || { FAILED_JOBS+=("sda1-anime"); FAILED_LOGS+=("$LOGFILE_SDA1"); }
JOBS_RUN+=1


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
  --log-file "$LOGFILE_SDB1" || { FAILED_JOBS+=("sdb1-media"); FAILED_LOGS+=("$LOGFILE_SDB1"); }
JOBS_RUN+=1


echo "Execution done."
