#!/bin/bash
# veracrypt-manager.sh — Mount and unmount VeraCrypt volumes
# veracrypt10 : mount/unmount only
# veracrypt11 : mount/unmount + docker start/stop
# Watchdog   : auto-unmount after IDLE_TIMEOUT seconds of no r/w activity
#
# ACTIVITY DETECTION (three tiers, evaluated each poll):
#   Tier 1 — inotifywait with event-count threshold (preferred)
#             A background inotifywait process counts filesystem events into a
#             counter file each poll window.  The watchdog resets the idle timer
#             only when the per-poll event delta meets INOTIFY_THRESHOLD (default 5).
#             This filters out Samba's own background noise (oplock polling,
#             directory stat calls) which typically produces 1–3 spurious events
#             per minute regardless of real user activity.
#             Requires: sudo apt install inotify-tools
#   Tier 2 — smbstatus -L (locked files)
#             Checks for SMB-locked files whose SharePath contains the
#             VeraCrypt mount point.  Works correctly; the old -S approach
#             showed share names, not paths, and never matched.
#   Tier 3 — /proc/diskstats delta (no-install fallback)
#             Compares read+write sector counters on the backing dm-crypt
#             device between polls.  Catches all I/O including SMB reads
#             that close before the poll fires.
#   Tier 4 — filesystem mtime (find -newer)
#             Catches local writes/deletes/renames (existing behaviour).
#   Tier 5 — open file handles (lsof)
#             Catches long-lived local handles open at poll time.
#
# SETUP NOTE — passwordless sudo for background watchdog
# The watchdog runs detached with no terminal; any sudo that prompts will hang.
# Add the following to /etc/sudoers via: sudo visudo
#
#   woeijiunn88 ALL=(ALL) NOPASSWD: /usr/bin/veracrypt, /usr/sbin/smbstatus
#
# Adjust the smbstatus path if needed: which smbstatus

# ─── Config ───────────────────────────────────────────────────────────────────

VC10_VOLUME="/mnt/sdb1/Documents/Q1BDVi5yYXI=.vmx"
VC10_MOUNT="/mnt/veracrypt10"
VC10_KEYFILE="/home/woeijiunn88/Documents/2FA/Keyfile/h1kW+P1h24s1zvHt9Z04Gw=="

VC11_VOLUME="/mnt/sdb1/Documents/RlBQLnJhcg==.vmx"
VC11_MOUNT="/mnt/veracrypt11"
VC11_KEYFILE="/home/woeijiunn88/Documents/2FA/Keyfile/h1kW+P1h24s1zvHt9Z04Gw=="
VC11_COMPOSE="/home/woeijiunn88/.docker/pigallery2-fpp/pigallery2.yml"
VC11_DOCKER_PORT=5777

IDLE_TIMEOUT=1200        # seconds before auto-unmount (20 min)
CHECK_INTERVAL=60        # watchdog poll frequency (seconds)
DOCKER_STOP_TIMEOUT=30   # seconds to wait for docker-compose stop
UNMOUNT_RETRIES=3        # how many times to retry a failed unmount

# Minimum inotify events per poll interval to count as real user activity.
# Samba background ops (oplock polling, dir stat calls) typically generate
# 1-3 spurious events/minute.  Set this above that noise floor.
# Raise if you still see false resets; lower if real SMB reads are missed.
INOTIFY_THRESHOLD=5

VC10_PID_FILE="/tmp/vc-watchdog-10.pid"
VC10_STAMP_FILE="/tmp/vc-watchdog-10.stamp"
VC10_LOG_FILE="/tmp/vc-watchdog-10.log"
VC10_INOTIFY_PID="/tmp/vc-inotify-10.pid"      # inotifywait watcher PID
VC10_IO_FILE="/tmp/vc-watchdog-10.io"           # diskstats sector counter
VC10_INOTIFY_CNT="/tmp/vc-inotify-10.count"    # cumulative inotify event counter

VC11_PID_FILE="/tmp/vc-watchdog-11.pid"
VC11_STAMP_FILE="/tmp/vc-watchdog-11.stamp"
VC11_LOG_FILE="/tmp/vc-watchdog-11.log"
VC11_INOTIFY_PID="/tmp/vc-inotify-11.pid"
VC11_IO_FILE="/tmp/vc-watchdog-11.io"
VC11_INOTIFY_CNT="/tmp/vc-inotify-11.count"

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Output helpers ───────────────────────────────────────────────────────────

info()  { echo -e "  $*"; }
ok()    { echo -e "  ${GREEN}✔${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $*"; }
err()   { echo -e "  ${RED}✘${RESET} $*" >&2; }
die()   { err "$*"; exit 1; }

fmt_duration() {
    local secs="${1:-0}"
    if [[ "$secs" -lt 0 ]] 2>/dev/null; then secs=0; fi
    printf "%dm %ds" $(( secs / 60 )) $(( secs % 60 ))
}

# ─── Preflight checks ─────────────────────────────────────────────────────────

check_deps() {
    local missing=()
    local cmd
    for cmd in veracrypt sudo mount find date grep awk lsof findmnt; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        die "Missing required commands: ${missing[*]}"
    fi
    if command -v inotifywait &>/dev/null; then
        ok "inotifywait found — SMB read activity detection is fully enabled."
    else
        warn "inotifywait not found — SMB read detection degraded."
        warn "  Install with: sudo apt install inotify-tools"
        warn "  Falling back to diskstats delta + smbstatus -L."
    fi
    command -v smbstatus &>/dev/null || \
        warn "smbstatus not found — SMB session detection via smbstatus disabled."
    command -v docker-compose &>/dev/null || \
        warn "docker-compose not found — vc11 Docker features will be unavailable."
}

check_sudo() {
    [[ $EUID -eq 0 ]] && die "Do not run as root. This script calls sudo internally where needed."
}

# ─── Mount helpers ────────────────────────────────────────────────────────────

# Anchored check — /mnt/vc1 must not match /mnt/vc10
is_mounted() {
    mount | awk '{print $3}' | grep -qx "$1"
}

preflight_mount() {
    local volume="$1" mount_point="$2" keyfile="$3" label="$4"
    local ok=true

    [[ -f "$volume" ]]      || { err "Volume file not found: $volume";          ok=false; }
    [[ -d "$mount_point" ]] || { err "Mount point missing: $mount_point";
                                  err "  Create it with: sudo mkdir -p $mount_point"; ok=false; }
    [[ -f "$keyfile" ]]     || { err "Keyfile not found: $keyfile";             ok=false; }
    is_mounted "$mount_point" && { err "$label is already mounted.";            ok=false; }

    $ok
}

# ─── Docker helpers ───────────────────────────────────────────────────────────

is_docker_running() {
    is_mounted "$VC11_MOUNT"             || return 1
    command -v docker-compose &>/dev/null || return 1
    docker-compose -f "$VC11_COMPOSE" ps 2>/dev/null | grep -q "Up"
}

docker_stop() {
    info "Stopping Docker services (timeout: ${DOCKER_STOP_TIMEOUT}s) ..."
    if docker-compose -f "$VC11_COMPOSE" stop -t "$DOCKER_STOP_TIMEOUT" 2>&1; then
        ok "Docker stopped."
        return 0
    else
        err "docker-compose stop returned an error."
        return 1
    fi
}

docker_start() {
    info "Starting Docker services ..."
    if ! docker-compose -f "$VC11_COMPOSE" up -d 2>&1; then
        err "docker-compose up failed."
        return 1
    fi
    sleep 2
    if is_docker_running; then
        ok "Docker started."
        if netstat -tuln 2>/dev/null | grep -q ":$VC11_DOCKER_PORT"; then
            ok "Port $VC11_DOCKER_PORT is accessible."
        else
            warn "Port $VC11_DOCKER_PORT not yet accessible — container may still be starting."
        fi
        return 0
    else
        err "Containers failed to reach 'Up' state."
        return 1
    fi
}

# ─── Unmount with retry ───────────────────────────────────────────────────────

do_unmount() {
    local mount_point="$1" label="$2"
    local attempt

    for (( attempt=1; attempt<=UNMOUNT_RETRIES; attempt++ )); do
        info "Unmounting ${CYAN}${label}${RESET} (attempt $attempt/$UNMOUNT_RETRIES) ..."
        sudo veracrypt -d "$mount_point" 2>&1 || true
        if ! is_mounted "$mount_point"; then
            ok "Unmounted successfully."
            return 0
        fi
        (( attempt < UNMOUNT_RETRIES )) && { warn "Still mounted — retrying in 5s ..."; sleep 5; }
    done

    err "Unmount of $label FAILED after $UNMOUNT_RETRIES attempts."
    err "  Check for open files: lsof +D $mount_point"
    return 1
}

# ─── Watchdog stamp helpers ───────────────────────────────────────────────────

reset_stamp() {
    date +%s > "$1" || { echo "ERROR: cannot write stamp file $1" >&2; return 1; }
}

# Activity extension — advances the stamp by CHECK_INTERVAL seconds.
# idle = now - stamp, so stamp += CHECK_INTERVAL reduces idle by CHECK_INTERVAL.
# Each active poll buys exactly one more poll interval of grace rather than
# fully resetting the idle counter to zero.
# Clamps so stamp never exceeds now (guards against backwards clock drift).
extend_stamp() {
    local stamp_file="$1"
    local last now extended
    last=$(cat "$stamp_file" 2>/dev/null)
    if [[ ! "$last" =~ ^[0-9]+$ ]]; then
        date +%s > "$stamp_file"
        return
    fi
    now=$(date +%s)
    extended=$(( last + CHECK_INTERVAL ))
    [[ "$extended" -gt "$now" ]] && extended="$now"
    echo "$extended" > "$stamp_file"
}

idle_seconds() {
    local stamp_file="$1"
    if [[ ! -f "$stamp_file" ]]; then
        echo "$IDLE_TIMEOUT"
        return
    fi
    local last
    last=$(cat "$stamp_file" 2>/dev/null) || { echo 0; return; }
    if [[ ! "$last" =~ ^[0-9]+$ ]]; then echo 0; return; fi
    local now diff
    now=$(date +%s)
    diff=$(( now - last ))
    if [[ "$diff" -lt 0 ]]; then diff=0; fi
    echo "$diff"
}

# ─── Activity detection — Tier 1: inotifywait watcher (event-classified) ──────
#
# Runs two parallel classification streams from a single inotifywait process.
# Events are split at read time by type and ISDIR flag:
#
#   STRONG events (MODIFY, CREATE, DELETE, MOVE, CLOSE_WRITE):
#     Any single occurrence means real user or application write activity.
#     Increments a separate strong-counter.  Threshold for strong = 1.
#     ISDIR variants are also counted — creating/deleting folders is real work.
#
#   WEAK events (ACCESS, CLOSE_NOWRITE on FILES ONLY — ISDIR stripped):
#     Directory ACCESS events (ACCESS,ISDIR) are the dominant source of false
#     positives.  They fire ~187 times per 60s when a Windows/macOS client has
#     a large folder open in Explorer/Finder due to directory change notification
#     polling, thumbnail generation, and Spotlight indexing.
#     Weak events are threshold-gated via INOTIFY_THRESHOLD (default 5).
#
# The watchdog checks strong_delta >= 1 OR weak_delta >= INOTIFY_THRESHOLD.
#
# IDENTIFYING YOUR NOISE:
#   Run this while idle to see which events/files are firing:
#     inotifywait -m -r -q -e access,modify,create,delete,move,close_write,\
#       close_nowrite --format '%T %e %w%f' --timefmt '%H:%M:%S' \
#       /mnt/veracrypt10 2>/dev/null | head -100

start_inotify_watcher() {
    local mount_point="$1" cnt_file="$2" pid_file="$3" log_file="$4"
    # strong counter file lives alongside cnt_file (weak counter)
    local strong_file="${cnt_file%.count}.strong"

    command -v inotifywait &>/dev/null || return 1

    stop_inotify_watcher "$pid_file"

    [[ -f "$cnt_file"    ]] || echo "0" > "$cnt_file"
    [[ -f "$strong_file" ]] || echo "0" > "$strong_file"

    (
        inotifywait -m -r -q \
            -e access,modify,create,delete,move,close_write,close_nowrite \
            --format '%e' \
            --exclude '/(\.Trash|\.veracrypt_user|\.DS_Store)' \
            "$mount_point" 2>/dev/null | \
        while IFS= read -r event; do
            local n
            case "$event" in
                # ── Strong: any write or structural change ─────────────────
                # Matches: MODIFY, CREATE, DELETE, MOVED_FROM, MOVED_TO,
                #          CLOSE_WRITE and their ,ISDIR variants.
                MODIFY*|CREATE*|DELETE*|MOVED_*|CLOSE_WRITE*)
                    n=$(cat "$strong_file" 2>/dev/null); [[ "$n" =~ ^[0-9]+$ ]] || n=0
                    echo $(( n + 1 )) > "$strong_file"
                    ;;
                # ── Weak: file reads only — strip directory ACCESS,ISDIR ──
                # ACCESS,ISDIR fires for every Explorer/Finder dir poll.
                # ACCESS (no ISDIR) is a genuine file read.
                # CLOSE_NOWRITE,ISDIR is also noise; CLOSE_NOWRITE (file) is real.
                ACCESS|CLOSE_NOWRITE)
                    n=$(cat "$cnt_file" 2>/dev/null); [[ "$n" =~ ^[0-9]+$ ]] || n=0
                    echo $(( n + 1 )) > "$cnt_file"
                    ;;
                # ACCESS,ISDIR / CLOSE_NOWRITE,ISDIR — directory polling noise, discard
                *)  ;;
            esac
        done
    ) &

    local wpid=$!
    disown "$wpid"
    echo "$wpid" > "$pid_file"
    echo "[$(date '+%F %T')] inotify watcher started (pid=$wpid) on $mount_point" \
         "(strong=any, weak_threshold=${INOTIFY_THRESHOLD})" >> "$log_file"
}

stop_inotify_watcher() {
    local pid_file="$1"
    [[ -f "$pid_file" ]] || return 0
    local pid
    pid=$(cat "$pid_file" 2>/dev/null) || { rm -f "$pid_file"; return 0; }
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        # Kill the inotifywait process group (watcher + pipeline reader)
        kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
}

# ─── Activity detection — Tier 2: smbstatus -L (locked files) ────────────────
#
# WHAT WAS BROKEN:
#   The original has_smb_session used 'smbstatus -S' which lists share
#   connections by *share name* (e.g. "Documents"), NOT by filesystem path.
#   Grepping for "/mnt/veracrypt10" in that output never matched anything,
#   so SMB sessions were silently ignored on every poll.
#
# THE FIX:
#   'smbstatus -L' lists files currently locked/open by SMB clients and
#   includes the full SharePath column — e.g. "/mnt/veracrypt10".  This
#   correctly detects any file a remote SMB client has open right now.
#
#   As a secondary check we also look up the Samba share name from smb.conf
#   and match it against 'smbstatus -S', which catches connected sessions
#   even when no individual file is currently locked.

# Return the Samba share name whose 'path =' directive matches the mount point.
smb_share_for_path() {
    local mount_point="$1"
    [[ -f /etc/samba/smb.conf ]] || return 1
    awk -v mp="$mount_point" '
        /^\[/ {
            # Extract share name between [ and ]
            share = substr($0, index($0,"[")+1)
            sub(/\].*/, "", share)
            gsub(/^[ \t]+|[ \t]+$/, "", share)
        }
        /path[ \t]*=/ {
            val = $0
            sub(/.*path[ \t]*=[ \t]*/, "", val)
            gsub(/[ \t]+$/, "", val)
            if (val == mp) { print share; exit }
        }
    ' /etc/samba/smb.conf 2>/dev/null | head -1
}

# Run smbstatus with optional sudo fallback; suppress PII from logs.
_smbstatus_run() {
    local flag="$1"
    local out
    out=$(smbstatus "$flag" 2>/dev/null)
    if [[ -z "$out" ]]; then
        out=$(sudo -n smbstatus "$flag" 2>/dev/null)
    fi
    echo "$out"
}

has_smb_session() {
    local mount_point="$1"
    command -v smbstatus &>/dev/null || return 1

    # Primary: locked files table — SharePath column contains the full path.
    # Any file open by an SMB client will appear here with its absolute path.
    if _smbstatus_run -L | grep -q "$mount_point"; then
        return 0
    fi

    # Secondary: share connection table — match by share name from smb.conf.
    # A connected SMB session persists even between individual file opens.
    local share_name
    share_name=$(smb_share_for_path "$mount_point")
    if [[ -n "$share_name" ]]; then
        if _smbstatus_run -S | awk 'NR>3 && NF' | grep -qi "^${share_name}[[:space:]]"; then
            return 0
        fi
    fi

    return 1
}

# ─── Activity detection — Tier 3: /proc/diskstats I/O delta ──────────────────
#
# Reads cumulative read+write sector counts for the backing dm-crypt device
# from /proc/diskstats and compares with the last stored value.  Any increase
# means I/O occurred since the last poll — including SMB reads that have
# already closed their handles.  Requires no extra packages.

# Resolve the block device backing a mount point (e.g. /dev/dm-2)
_backing_device() {
    local mount_point="$1"
    findmnt -n -o SOURCE "$mount_point" 2>/dev/null | head -1
}

has_diskio_activity() {
    local mount_point="$1" io_file="$2"
    [[ -f /proc/diskstats ]] || return 1

    local dev
    dev=$(_backing_device "$mount_point")
    [[ -z "$dev" ]] && return 1

    # Strip /dev/ prefix; handle dm-N names (e.g. /dev/dm-2 → dm-2)
    local devname="${dev##*/}"

    # Fields: major minor name reads_completed reads_merged sectors_read
    #         read_ms writes_completed writes_merged sectors_written write_ms ...
    # We sum field 6 (sectors_read) + field 10 (sectors_written)
    local sectors_now
    sectors_now=$(awk -v d="$devname" '$3==d {print $6+$10; exit}' /proc/diskstats 2>/dev/null)
    [[ -z "$sectors_now" || ! "$sectors_now" =~ ^[0-9]+$ ]] && return 1

    if [[ -f "$io_file" ]]; then
        local sectors_last
        sectors_last=$(cat "$io_file" 2>/dev/null)
        echo "$sectors_now" > "$io_file"
        if [[ "$sectors_last" =~ ^[0-9]+$ ]] && (( sectors_now > sectors_last )); then
            return 0   # I/O occurred since last poll
        fi
    else
        echo "$sectors_now" > "$io_file"
    fi

    return 1
}

# ─── Activity detection — Tier 4: filesystem mtime (original) ────────────────
#
# Catches local writes, deletes, renames via find -newer.
# Does NOT catch reads (atime is usually suppressed by relatime/noatime).

has_activity() {
    local mount_point="$1" stamp_file="$2"
    [[ -f "$stamp_file" && -d "$mount_point" ]] || return 1
    local hit
    hit=$(find "$mount_point" \
            -newer "$stamp_file" \
            -not -path '*/.Trash*' \
            -not -name '.veracrypt_user' \
            -not -name '.DS_Store' \
            2>/dev/null | head -1)
    [[ -n "$hit" ]]
}

# ─── Activity detection — Tier 5: open file handles (original) ───────────────
#
# Catches local processes and long-lived file descriptors still open at poll time.
# Output suppressed — no paths or filenames are logged.

has_open_handles() {
    local mount_point="$1"
    [[ -d "$mount_point" ]] || return 1
    lsof +D "$mount_point" 2>/dev/null | grep -q .
}

# ─── Watchdog PID management ─────────────────────────────────────────────────

watchdog_running() {
    local pid_file="$1"
    [[ -f "$pid_file" ]] || return 1
    local pid
    pid=$(cat "$pid_file" 2>/dev/null) || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

kill_watchdog() {
    local pid_file="$1" inotify_pid_file="${2:-}"

    # Stop the inotify watcher first so it doesn't interfere with unmount
    [[ -n "$inotify_pid_file" ]] && stop_inotify_watcher "$inotify_pid_file"

    [[ -f "$pid_file" ]] || return 0
    local pid
    pid=$(cat "$pid_file" 2>/dev/null) || { rm -f "$pid_file"; return 0; }
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        local i; for i in 1 2 3; do
            sleep 1
            kill -0 "$pid" 2>/dev/null || break
        done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
}

# ─── Watchdog loop (runs as detached background process) ──────────────────────

watchdog_loop() {
    local mount_point="$1" stamp_file="$2" pid_file="$3"
    local log_file="$4" label="$5" compose_file="${6:-}"
    local inotify_pid_file io_file cnt_file last_cnt_file

    # Derive companion file paths from the watchdog PID file base name
    inotify_pid_file="${pid_file/watchdog/inotify}"
    io_file="${pid_file%.pid}.io"
    cnt_file="${pid_file/watchdog/inotify}"
    cnt_file="${cnt_file%.pid}.count"
    last_cnt_file="${cnt_file%.count}.lastcount"
    strong_file="${cnt_file%.count}.strong"
    last_strong_file="${cnt_file%.count}.laststrong"

    exec >> "$log_file" 2>&1

    echo "$BASHPID" > "$pid_file"

    wlog() { echo "[$(date '+%F %T')] $*"; }
    wmount_check() { mount | awk '{print $3}' | grep -qx "$mount_point"; }

    reset_stamp "$stamp_file"
    wlog "=== Watchdog started: $label | pid=$BASHPID | timeout=${IDLE_TIMEOUT}s | poll=${CHECK_INTERVAL}s | inotify_threshold=${INOTIFY_THRESHOLD} ==="

    # ── Tier 1: start the inotifywait watcher ──────────────────────────────
    # strong_file: write/structural events (any delta >= 1 triggers reset)
    # cnt_file:    file-read events only, ISDIR stripped (threshold-gated)
    if command -v inotifywait &>/dev/null; then
        start_inotify_watcher "$mount_point" "$cnt_file" "$inotify_pid_file" "$log_file"
        cat "$cnt_file"    2>/dev/null > "$last_cnt_file"    || echo "0" > "$last_cnt_file"
        cat "$strong_file" 2>/dev/null > "$last_strong_file" || echo "0" > "$last_strong_file"
    else
        wlog "inotifywait unavailable — using diskstats delta + smbstatus fallback."
    fi

    # Initialise the diskstats baseline so the first poll computes a clean delta
    has_diskio_activity "$mount_point" "$io_file" 2>/dev/null || true

    local consecutive_fail=0

    while true; do
        sleep "$CHECK_INTERVAL"

        # Exit cleanly if volume was manually unmounted
        if ! wmount_check; then
            wlog "Volume $label no longer mounted — watchdog exiting."
            stop_inotify_watcher "$inotify_pid_file"
            rm -f "$pid_file" "$io_file"
            exit 0
        fi

        # ── Tier 1 check: classified inotify event deltas ──────────────────
        # Strong delta (writes/structural): any occurrence = real activity.
        # Weak delta (file reads, ISDIR stripped): threshold-gated.
        if [[ -f "$strong_file" && -f "$last_strong_file" ]]; then
            local s_now s_last s_delta
            s_now=$(cat "$strong_file" 2>/dev/null);    [[ "$s_now"  =~ ^[0-9]+$ ]] || s_now=0
            s_last=$(cat "$last_strong_file" 2>/dev/null); [[ "$s_last" =~ ^[0-9]+$ ]] || s_last=0
            s_delta=$(( s_now - s_last ))
            echo "$s_now" > "$last_strong_file"
            if [[ "$s_delta" -ge 1 ]]; then
                wlog "inotify: ${s_delta} write/structural event(s) on $label — +${CHECK_INTERVAL}s grace."
                extend_stamp "$stamp_file"
                consecutive_fail=0
                continue
            fi
        fi

        if [[ -f "$cnt_file" && -f "$last_cnt_file" ]]; then
            local cnt_now cnt_last delta
            cnt_now=$(cat "$cnt_file" 2>/dev/null);  [[ "$cnt_now"  =~ ^[0-9]+$ ]] || cnt_now=0
            cnt_last=$(cat "$last_cnt_file" 2>/dev/null); [[ "$cnt_last" =~ ^[0-9]+$ ]] || cnt_last=0
            delta=$(( cnt_now - cnt_last ))
            echo "$cnt_now" > "$last_cnt_file"

            if [[ "$delta" -ge "$INOTIFY_THRESHOLD" ]]; then
                wlog "inotify: ${delta} file-read event(s) this poll (threshold=${INOTIFY_THRESHOLD}) on $label — +${CHECK_INTERVAL}s grace."
                extend_stamp "$stamp_file"
                consecutive_fail=0
                continue
            elif [[ "$delta" -gt 0 ]]; then
                wlog "inotify: ${delta} events this poll — below threshold (${INOTIFY_THRESHOLD}), treating as background noise."
            fi
        fi

        # ── Tier 2: smbstatus -L (locked files with full paths) ────────────
        if has_smb_session "$mount_point"; then
            wlog "Active SMB session/locked file on $label — +${CHECK_INTERVAL}s grace."
            extend_stamp "$stamp_file"
            consecutive_fail=0
            continue
        fi

        # ── Tier 3: /proc/diskstats I/O delta ──────────────────────────────
        if has_diskio_activity "$mount_point" "$io_file"; then
            wlog "Block device I/O detected on $label — +${CHECK_INTERVAL}s grace."
            extend_stamp "$stamp_file"
            consecutive_fail=0
            continue
        fi

        # ── Tier 4: filesystem mtime changes (writes/deletes/renames) ──────
        if has_activity "$mount_point" "$stamp_file"; then
            wlog "Filesystem mtime activity on $label — +${CHECK_INTERVAL}s grace."
            extend_stamp "$stamp_file"
            consecutive_fail=0
            continue
        fi

        # ── Tier 5: open file handles at poll time ──────────────────────────
        if has_open_handles "$mount_point"; then
            wlog "Open handles on $label — +${CHECK_INTERVAL}s grace."
            extend_stamp "$stamp_file"
            consecutive_fail=0
            continue
        fi

        # All tiers passed with no activity — advance idle counter
        idle=$(idle_seconds "$stamp_file")
        wlog "Idle: ${idle}s / ${IDLE_TIMEOUT}s on $label"

        if [[ "$idle" -lt "$IDLE_TIMEOUT" ]]; then continue; fi

        wlog "=== Idle timeout reached — initiating auto-unmount of $label ==="

        # Stop inotify watcher before unmounting to avoid spurious events
        stop_inotify_watcher "$inotify_pid_file"

        # Stop Docker before unmounting (vc11 only), with back-off on repeated failure
        if [[ -n "$compose_file" ]]; then
            wlog "Stopping Docker services ..."
            if ! docker-compose -f "$compose_file" stop -t "$DOCKER_STOP_TIMEOUT"; then
                consecutive_fail=$(( consecutive_fail + 1 ))
                wlog "ERROR: Docker stop failed (attempt $consecutive_fail)."
                if [[ "$consecutive_fail" -lt 3 ]]; then
                    wlog "Backing off — will retry after ${IDLE_TIMEOUT}s."
                    reset_stamp "$stamp_file"
                    # Restart inotify watcher during back-off period
                    command -v inotifywait &>/dev/null && \
                        start_inotify_watcher "$mount_point" "$cnt_file" \
                                              "$inotify_pid_file" "$log_file"
                    continue
                else
                    wlog "Docker stop failed $consecutive_fail times — forcing unmount anyway."
                fi
            else
                wlog "Docker stopped."
                consecutive_fail=0
            fi
        fi

        # Unmount with retries
        local attempt unmounted=false
        for (( attempt=1; attempt<=UNMOUNT_RETRIES; attempt++ )); do
            wlog "Unmount attempt $attempt/$UNMOUNT_RETRIES ..."
            sudo veracrypt -d "$mount_point" 2>&1 || true
            sleep 2
            if ! wmount_check; then
                unmounted=true
                break
            fi
            wlog "Still mounted — waiting 5s ..."
            sleep 5
        done

        if $unmounted; then
            wlog "=== Auto-unmount of $label successful. Watchdog done. ==="
            rm -f "$pid_file" "$stamp_file" "$io_file" \
                  "$cnt_file" "$last_cnt_file" "$strong_file" "$last_strong_file"
            exit 0
        else
            wlog "ERROR: Unmount failed after $UNMOUNT_RETRIES attempts — backing off ${IDLE_TIMEOUT}s."
            reset_stamp "$stamp_file"
            consecutive_fail=$(( consecutive_fail + 1 ))
            # Restart inotify watcher during back-off period
            command -v inotifywait &>/dev/null && \
                start_inotify_watcher "$mount_point" "$cnt_file" \
                                      "$inotify_pid_file" "$log_file"
        fi
    done
}

# ─── Start watchdog ───────────────────────────────────────────────────────────

start_watchdog() {
    local pid_file="$3" log_file="$4"

    kill_watchdog "$pid_file"
    [[ -f "$log_file" ]] && mv "$log_file" "${log_file}.prev"

    watchdog_loop "$@" &
    local wdpid=$!
    disown "$wdpid"

    echo "$wdpid" > "$pid_file"
    sleep 0.3

    if watchdog_running "$pid_file"; then
        ok "Watchdog started (pid=$(cat "$pid_file")). Log: $log_file"
    else
        err "Watchdog process failed to start — check: $log_file"
        return 1
    fi
}

# ─── veracrypt10 — mount / unmount ────────────────────────────────────────────

mount_vc10() {
    if is_mounted "$VC10_MOUNT"; then
        warn "veracrypt10 is already mounted — skipping."
        return 0
    fi
    preflight_mount "$VC10_VOLUME" "$VC10_MOUNT" "$VC10_KEYFILE" "veracrypt10" || return 1
    info "Mounting ${CYAN}veracrypt10${RESET} at $VC10_MOUNT ..."
    sudo veracrypt --text "$VC10_VOLUME" "$VC10_MOUNT" \
        -k "$VC10_KEYFILE" --protect-hidden=no || true

    if is_mounted "$VC10_MOUNT"; then
        ok "Mounted at $VC10_MOUNT."
        info "Starting idle watchdog (auto-unmount after $(fmt_duration $IDLE_TIMEOUT) idle) ..."
        start_watchdog "$VC10_MOUNT" "$VC10_STAMP_FILE" "$VC10_PID_FILE" \
                       "$VC10_LOG_FILE" "veracrypt10"
    else
        err "Mount failed — volume not in mount table."
        return 1
    fi
}

unmount_vc10() {
    if ! is_mounted "$VC10_MOUNT"; then
        warn "veracrypt10 is not mounted — skipping."
        return 0
    fi
    if watchdog_running "$VC10_PID_FILE"; then
        info "Stopping watchdog for ${CYAN}veracrypt10${RESET} ..."
        kill_watchdog "$VC10_PID_FILE" "$VC10_INOTIFY_PID"
        rm -f "$VC10_STAMP_FILE" "$VC10_IO_FILE" \
              "$VC10_INOTIFY_CNT" "${VC10_INOTIFY_CNT/%.count/.lastcount}" \
              "${VC10_INOTIFY_CNT/%.count/.strong}" "${VC10_INOTIFY_CNT/%.count/.laststrong}"
    else
        stop_inotify_watcher "$VC10_INOTIFY_PID"
    fi
    do_unmount "$VC10_MOUNT" "veracrypt10"
}

do_vc10() {
    if is_mounted "$VC10_MOUNT"; then unmount_vc10; else mount_vc10; fi
}

# ─── veracrypt11 — mount / unmount + docker ───────────────────────────────────

mount_vc11() {
    if is_mounted "$VC11_MOUNT"; then
        warn "veracrypt11 is already mounted — skipping."
        return 0
    fi
    preflight_mount "$VC11_VOLUME" "$VC11_MOUNT" "$VC11_KEYFILE" "veracrypt11" || return 1
    [[ -f "$VC11_COMPOSE" ]] || { err "Compose file not found: $VC11_COMPOSE"; return 1; }

    info "Mounting ${CYAN}veracrypt11${RESET} at $VC11_MOUNT ..."
    sudo veracrypt --text "$VC11_VOLUME" "$VC11_MOUNT" \
        -k "$VC11_KEYFILE" --protect-hidden=no || true

    if ! is_mounted "$VC11_MOUNT"; then
        err "Mount failed — volume not in mount table."
        return 1
    fi
    ok "Mounted at $VC11_MOUNT."

    if ! docker_start; then
        err "Docker failed. Rolling back — unmounting $VC11_MOUNT ..."
        do_unmount "$VC11_MOUNT" "veracrypt11" || \
            err "Rollback unmount also failed — manual intervention required."
        return 1
    fi

    info "Starting idle watchdog (auto-unmount+stop docker after $(fmt_duration $IDLE_TIMEOUT) idle) ..."
    start_watchdog "$VC11_MOUNT" "$VC11_STAMP_FILE" "$VC11_PID_FILE" \
                   "$VC11_LOG_FILE" "veracrypt11" "$VC11_COMPOSE"
}

unmount_vc11() {
    if ! is_mounted "$VC11_MOUNT"; then
        warn "veracrypt11 is not mounted — skipping."
        return 0
    fi
    if watchdog_running "$VC11_PID_FILE"; then
        info "Stopping watchdog for ${CYAN}veracrypt11${RESET} ..."
        kill_watchdog "$VC11_PID_FILE" "$VC11_INOTIFY_PID"
        rm -f "$VC11_STAMP_FILE" "$VC11_IO_FILE" \
              "$VC11_INOTIFY_CNT" "${VC11_INOTIFY_CNT/%.count/.lastcount}" \
              "${VC11_INOTIFY_CNT/%.count/.strong}" "${VC11_INOTIFY_CNT/%.count/.laststrong}"
    else
        stop_inotify_watcher "$VC11_INOTIFY_PID"
    fi

    if is_docker_running; then
        docker_stop || warn "Docker stop had errors — proceeding with unmount anyway."
    else
        warn "Docker was not running."
    fi

    do_unmount "$VC11_MOUNT" "veracrypt11" || return 1
}

do_vc11() {
    if is_mounted "$VC11_MOUNT"; then unmount_vc11; else mount_vc11; fi
}

# ─── Status table ─────────────────────────────────────────────────────────────

show_status() {
    local vc10_mount vc11_mount docker_info port_info vc10_wd vc11_wd

    if is_mounted "$VC10_MOUNT"; then
        vc10_mount="${GREEN}mounted${RESET}"
    else
        vc10_mount="${YELLOW}unmounted${RESET}"
    fi

    if is_mounted "$VC11_MOUNT"; then
        vc11_mount="${GREEN}mounted${RESET}"
        if is_docker_running; then
            docker_info="${GREEN}docker: up${RESET}"
        else
            docker_info="${YELLOW}docker: down${RESET}"
        fi
        if netstat -tuln 2>/dev/null | grep -q ":$VC11_DOCKER_PORT"; then
            port_info="${GREEN}:${VC11_DOCKER_PORT} ok${RESET}"
        else
            port_info="${YELLOW}:${VC11_DOCKER_PORT} n/a${RESET}"
        fi
    else
        vc11_mount="${YELLOW}unmounted${RESET}"
        docker_info="${YELLOW}docker: —${RESET}"
        port_info=""
    fi

    _wd_status() {
        local pid_file="$1" stamp_file="$2" inotify_pid="$3"
        if watchdog_running "$pid_file"; then
            local idle remain inotify_note=""
            idle=$(idle_seconds "$stamp_file")
            remain=$(( IDLE_TIMEOUT - idle ))
            if [[ "$remain" -lt 0 ]]; then remain=0; fi
            if [[ -f "$inotify_pid" ]] && kill -0 "$(cat "$inotify_pid" 2>/dev/null)" 2>/dev/null; then
                inotify_note=" ${CYAN}[inotify ✔]${RESET}"
            else
                inotify_note=" ${YELLOW}[inotify ✘]${RESET}"
            fi
            echo -e "${GREEN}watchdog on${RESET}${inotify_note} — idle $(fmt_duration $idle), auto-off in $(fmt_duration $remain)"
        else
            echo -e "${YELLOW}watchdog off${RESET}"
        fi
    }

    vc10_wd=$(_wd_status "$VC10_PID_FILE" "$VC10_STAMP_FILE" "$VC10_INOTIFY_PID")
    vc11_wd=$(_wd_status "$VC11_PID_FILE" "$VC11_STAMP_FILE" "$VC11_INOTIFY_PID")

    echo ""
    printf "  %-4s  %-14s  %-13s  %s\n" "No." "Volume" "State" "Info"
    printf "  %-4s  %-14s  %-13s  %s\n" "---" "------" "-----" "----"

    printf "  %-4s  %-14s  " "1" "veracrypt10"
    echo -e -n "$vc10_mount"
    echo -e "  │  $vc10_wd"

    printf "  %-4s  %-14s  " "2" "veracrypt11"
    echo -e -n "$vc11_mount"
    echo -e "  │  $docker_info  $port_info"
    printf "  %-32s  │  %s\n" "" "$(echo -e "$vc11_wd")"

    echo ""
    echo -e "  ${CYAN}Timeout: $(fmt_duration $IDLE_TIMEOUT)  │  Poll: ${CHECK_INTERVAL}s  │  Unmount retries: ${UNMOUNT_RETRIES}${RESET}"
    echo -e "  ${BOLD}Options:${RESET} 1/2=toggle  a=mount both  u=unmount both  u1/u2=unmount one  w=watchdog  q=quit"
    echo ""
}

# ─── Watchdog management submenu ─────────────────────────────────────────────

do_watchdog_menu() {
    echo -e "\n  ${BOLD}Watchdog Manager${RESET}"
    echo ""
    printf "  ${CYAN}%-4s${RESET}  %s\n" "k1" "Kill vc10 watchdog"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "k2" "Kill vc11 watchdog"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "r1" "Restart vc10 watchdog (must be mounted)"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "r2" "Restart vc11 watchdog (must be mounted)"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "l1" "Tail vc10 log"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "l2" "Tail vc11 log"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "p1" "Previous vc10 log session"
    printf "  ${CYAN}%-4s${RESET}  %s\n" "p2" "Previous vc11 log session"
    echo ""
    read -rp "  Choice: " WOPT
    echo ""

    case "${WOPT,,}" in
        k1) kill_watchdog "$VC10_PID_FILE" "$VC10_INOTIFY_PID"
            rm -f "$VC10_STAMP_FILE" "$VC10_IO_FILE" \
                  "$VC10_INOTIFY_CNT" "${VC10_INOTIFY_CNT/%.count/.lastcount}" \
                  "${VC10_INOTIFY_CNT/%.count/.strong}" "${VC10_INOTIFY_CNT/%.count/.laststrong}"
            warn "veracrypt10 watchdog killed." ;;
        k2) kill_watchdog "$VC11_PID_FILE" "$VC11_INOTIFY_PID"
            rm -f "$VC11_STAMP_FILE" "$VC11_IO_FILE" \
                  "$VC11_INOTIFY_CNT" "${VC11_INOTIFY_CNT/%.count/.lastcount}" \
                  "${VC11_INOTIFY_CNT/%.count/.strong}" "${VC11_INOTIFY_CNT/%.count/.laststrong}"
            warn "veracrypt11 watchdog killed." ;;
        r1) if is_mounted "$VC10_MOUNT"; then
                start_watchdog "$VC10_MOUNT" "$VC10_STAMP_FILE" "$VC10_PID_FILE" \
                               "$VC10_LOG_FILE" "veracrypt10"
            else err "veracrypt10 is not mounted."; fi ;;
        r2) if is_mounted "$VC11_MOUNT"; then
                start_watchdog "$VC11_MOUNT" "$VC11_STAMP_FILE" "$VC11_PID_FILE" \
                               "$VC11_LOG_FILE" "veracrypt11" "$VC11_COMPOSE"
            else err "veracrypt11 is not mounted."; fi ;;
        l1) tail -50 "$VC10_LOG_FILE"          2>/dev/null || warn "No log: $VC10_LOG_FILE" ;;
        l2) tail -50 "$VC11_LOG_FILE"          2>/dev/null || warn "No log: $VC11_LOG_FILE" ;;
        p1) tail -50 "${VC10_LOG_FILE}.prev"   2>/dev/null || warn "No prev log." ;;
        p2) tail -50 "${VC11_LOG_FILE}.prev"   2>/dev/null || warn "No prev log." ;;
        *)  err "Invalid option." ;;
    esac
}

# ─── Entry point ──────────────────────────────────────────────────────────────

main() {
    check_deps
    check_sudo

    echo -e "\n${BOLD}VeraCrypt Manager${RESET}"
    show_status

    read -rp "  Select [1/2/a/u/u1/u2/w/q]: " OPT
    echo ""

    case "${OPT,,}" in
        1)    do_vc10 ;;
        2)    do_vc11 ;;
        a)    mount_vc10; echo ""; mount_vc11 ;;
        u)    unmount_vc11; echo ""; unmount_vc10 ;;
        u1)   unmount_vc10 ;;
        u2)   unmount_vc11 ;;
        w)    do_watchdog_menu ;;
        q|"") exit 0 ;;
        *)    err "Invalid option."; exit 1 ;;
    esac

    echo ""
    show_status
}

main "$@"