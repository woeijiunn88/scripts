#!/usr/bin/env bash
# ==============================================================================
# apple-reprocess.sh
#
# Re-categorizes all files under /mnt/sdb1/Backup/Apple into the correct
# folders based on EXIF data, using the same logic as the sync script.
#
# Safe to run multiple times — files already in the correct folder are skipped.
# Requires: exiftool, python3
# ==============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
BACKUP_ROOT="/mnt/sdb1/Backup/Apple"
CAMERA_DIR="$BACKUP_ROOT/Camera"
SCREENSHOTS_DIR="$BACKUP_ROOT/Screenshots"
SCREEN_RECORDINGS_DIR="$BACKUP_ROOT/Screen Recordings"
OTHERS_DIR="$BACKUP_ROOT/Others"
GMT_OFFSET=8
LOG_FILE="$HOME/.log/icloud/reprocess_$(TZ=Asia/Kuala_Lumpur date '+%Y%m%d_%H%M%S').log"

# ── Setup ──────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

log()      { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"; }
die()      { log "ERROR: $*"; exit 1; }
need_cmd() { command -v "$1" &>/dev/null || die "Missing required command: $1"; }

_err_trap() { log "ERROR: Unexpected exit at line $1 (exit code $2)"; }
trap '_err_trap $LINENO $?' ERR

need_cmd exiftool
need_cmd python3

log "Starting reprocess — root: $BACKUP_ROOT"
[[ -d "$BACKUP_ROOT" ]] || die "$BACKUP_ROOT is not mounted or does not exist"

mkdir -p "$CAMERA_DIR" "$SCREENSHOTS_DIR" "$SCREEN_RECORDINGS_DIR" "$OTHERS_DIR"

# ── Temp files ─────────────────────────────────────────────────────────────────
SRC_LIST=$(mktemp)
EXIF_JSON=$(mktemp)
MOVE_LIST=$(mktemp)
MTIME_LIST=$(mktemp)
trap 'rm -f "$SRC_LIST" "$EXIF_JSON" "$MOVE_LIST" "$MTIME_LIST"' EXIT

# ── Find all files across all category folders ────────────────────────────────
log "Scanning $BACKUP_ROOT ..."
find "$CAMERA_DIR" "$SCREENSHOTS_DIR" "$SCREEN_RECORDINGS_DIR" "$OTHERS_DIR" \
    -type f \
    \( -iname "*.jpg"  -o -iname "*.jpeg" \
       -o -iname "*.png" \
       -o -iname "*.heic" -o -iname "*.heif" \
       -o -iname "*.dng" \
       -o -iname "*.mov"  -o -iname "*.mp4" \
       -o -iname "*.m4v"  -o -iname "*.3gp" \) \
    -print 2>/dev/null > "$SRC_LIST" || true

TOTAL=$(wc -l < "$SRC_LIST")
if [[ "$TOTAL" -eq 0 ]]; then
    log "No files found under $BACKUP_ROOT — nothing to do."
    exit 0
fi
log "Found $TOTAL file(s) to evaluate."

# ── Batch EXIF in chunks of 50 ────────────────────────────────────────────────
mapfile -t ALL_FILES < "$SRC_LIST"
BATCH_SIZE=50
TOTAL_FILES=${#ALL_FILES[@]}
echo "[" > "$EXIF_JSON"
FIRST_ENTRY=1

for (( i=0; i<TOTAL_FILES; i+=BATCH_SIZE )); do
    BATCH=("${ALL_FILES[@]:$i:$BATCH_SIZE}")
    BATCH_TMP=$(mktemp)
    CHUNK_TMP=$(mktemp)
    printf '%s\n' "${BATCH[@]}" > "$BATCH_TMP"

    exiftool -j -q \
        -Make -Description -ImageDescription -UserComment -ImageCaptureType -Author \
        -DateTimeOriginal -OffsetTimeOriginal -SubSecTimeOriginal \
        -CreationDate -MediaCreateDate \
        -@ "$BATCH_TMP" > "$CHUNK_TMP" 2>/dev/null || echo "[]" > "$CHUNK_TMP"
    rm -f "$BATCH_TMP"

    python3 - "$CHUNK_TMP" "$EXIF_JSON" "$FIRST_ENTRY" <<'PYEOF'
import sys, json
chunk_path  = sys.argv[1]
out_path    = sys.argv[2]
first_entry = sys.argv[3] == '1'
try:
    with open(chunk_path) as f:
        items = json.load(f)
except Exception:
    items = []
if not items:
    sys.exit(0)
with open(out_path, 'a') as fout:
    for idx, item in enumerate(items):
        if not first_entry or idx > 0:
            fout.write(',\n')
        fout.write(json.dumps(item))
PYEOF

    rm -f "$CHUNK_TMP"
    FIRST_ENTRY=0
    DONE=$(( i + ${#BATCH[@]} ))
    log "  EXIF progress: $DONE/$TOTAL_FILES"
done

echo "]" >> "$EXIF_JSON"

# ── Categorize and build move list ────────────────────────────────────────────
export _GMT_OFFSET="$GMT_OFFSET"
export _CAMERA_DIR="$CAMERA_DIR"
export _SCREENSHOTS_DIR="$SCREENSHOTS_DIR"
export _SCREEN_RECORDINGS_DIR="$SCREEN_RECORDINGS_DIR"
export _OTHERS_DIR="$OTHERS_DIR"
export _MOVE_LIST="$MOVE_LIST"
export _EXIF_JSON="$EXIF_JSON"
export _SRC_LIST="$SRC_LIST"

python3 <<'PYEOF'
import json, re, os
from datetime import datetime, timezone, timedelta

gmt_h          = int(os.environ['_GMT_OFFSET'])
camera_dir     = os.environ['_CAMERA_DIR']
shots_dir      = os.environ['_SCREENSHOTS_DIR']
recordings_dir = os.environ['_SCREEN_RECORDINGS_DIR']
others_dir     = os.environ['_OTHERS_DIR']
move_list      = os.environ['_MOVE_LIST']
exif_json      = os.environ['_EXIF_JSON']
src_list       = os.environ['_SRC_LIST']

with open(src_list) as f:
    src_files = [line.rstrip('\n') for line in f if line.strip()]

gmt8     = timezone(timedelta(hours=gmt_h))
vid_exts = {'mov', 'mp4', 'm4v', '3gp'}
ios_re   = re.compile(r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(\d{3})_iOS\.(\w+)$')

def filename_to_gmt8(fname, ext):
    m = ios_re.match(fname)
    if not m:
        return ''
    Y,Mo,D,H,Mi,S,ms,_ = m.groups()
    dt = datetime(int(Y),int(Mo),int(D),int(H),int(Mi),int(S),
                  int(ms)*1000, tzinfo=timezone.utc) + timedelta(hours=gmt_h)
    return dt.strftime('%Y%m%d_%H%M') + f'{dt.second:02d}{int(ms):03d}_iOS.{ext}'

def meta_to_gmt8(raw_dt, offset, subsec, ext):
    if not raw_dt:
        return ''
    try:
        d = raw_dt.strip().replace(':', '-', 2)
        if '+' in d[10:] or (len(d) > 19 and d[19] == '-'):
            dt = datetime.fromisoformat(d)
        elif offset:
            dt = datetime.fromisoformat(d + offset.strip())
        else:
            dt = datetime.fromisoformat(d).replace(tzinfo=timezone.utc)
        dt8 = dt.astimezone(gmt8)
    except Exception:
        return ''
    ms = int(subsec.ljust(3,'0')[:3]) if subsec else 0
    return dt8.strftime('%Y%m%d_%H%M') + f'{dt8.second:02d}{ms:03d}_iOS.{ext}'

def g(d, k):
    return str(d.get(k) or '').strip()

try:
    with open(exif_json) as f:
        exif_list = json.load(f)
except Exception:
    exif_list = []

exif_map = {e.get('SourceFile', ''): e for e in exif_list}

queued = skipped = 0

with open(move_list, 'w') as fout:
    for fpath in src_files:
        basename = os.path.basename(fpath)
        ext      = basename.rsplit('.', 1)[-1].lower() if '.' in basename else ''
        is_video = ext in vid_exts
        d        = exif_map.get(fpath, {})

        make          = g(d, 'Make')
        description   = g(d, 'Description').lower()
        img_desc      = g(d, 'ImageDescription').lower()
        user_comment  = g(d, 'UserComment').lower()
        image_capture = g(d, 'ImageCaptureType')
        author        = g(d, 'Author').lower()
        creation_dt   = g(d, 'CreationDate')
        date_orig     = g(d, 'DateTimeOriginal')
        offset_orig   = g(d, 'OffsetTimeOriginal')
        subsec        = g(d, 'SubSecTimeOriginal')
        media_dt      = g(d, 'MediaCreateDate')

        is_screenshot = any(
            'screenshot' in f or 'screen shot' in f
            for f in (description, img_desc, user_comment)
        )

        is_screen_recording = (
            is_video and (
                'replaykit' in author or 'recording' in author or not make
            ) and not (make.lower() == 'apple' and creation_dt)
        )

        is_camera_video = (
            is_video and make.lower() == 'apple' and
            creation_dt and not is_screen_recording
        )

        # ImageCaptureType values that represent a direct native Camera app capture.
        # Absent tag ('') covers older iOS that doesn't set it.
        # Anything else (Portrait, SlowMo, Video, TimeLapse, Panorama, …) → Others.
        NATIVE_CAPTURE_TYPES = {'', 'scene', 'standard', 'photo'}
        is_native_capture = image_capture.lower() in NATIVE_CAPTURE_TYPES

        is_proraw_export = (not is_video and image_capture == 'ProRAW' and ext in ('jpg', 'jpeg'))
        is_camera_image  = (not is_video and not is_screenshot and not is_proraw_export and
                            is_native_capture and
                            (ext == 'dng' or (make.lower() == 'apple' and offset_orig)))

        if is_camera_video:
            category, dest_dir = 'Camera', camera_dir
        elif is_screen_recording:
            category, dest_dir = 'Screen Recordings', recordings_dir
        elif is_video:
            category, dest_dir = 'Others', others_dir
        elif is_screenshot:
            category, dest_dir = 'Screenshots', shots_dir
        elif is_camera_image:
            category, dest_dir = 'Camera', camera_dir
        else:
            category, dest_dir = 'Others', others_dir

        # Build correct filename
        new_name = ''
        if is_video:
            new_name = meta_to_gmt8(creation_dt, '', '', ext) or \
                       meta_to_gmt8(media_dt, '', '', ext)
        elif category == 'Camera' and date_orig:
            new_name = meta_to_gmt8(date_orig, offset_orig, subsec, ext)
        new_name = new_name or filename_to_gmt8(basename, ext) or basename

        dest_path = os.path.join(dest_dir, new_name)

        # Skip only if source and destination resolve to the exact same path
        if os.path.realpath(fpath) == os.path.realpath(dest_path):
            skipped += 1
            continue

        fout.write(f'{fpath}\t{dest_dir}\t{new_name}\t{category}\n')
        queued += 1

# Write counts to a separate fd so bash can read them even with exec redirect
with open('/dev/stderr', 'w') as ferr:
    ferr.write(f'__COUNTS__ queued={queued} skipped={skipped}\n')
PYEOF

# ── Parse queued count directly from MOVE_LIST ────────────────────────────────
QUEUED=$(wc -l < "$MOVE_LIST")
QUEUED="${QUEUED// /}"   # trim whitespace
log "Queued to move: $QUEUED file(s)"

if [[ "$QUEUED" -eq 0 ]]; then
    log "All files already in correct folders — nothing to move."
    exit 0
fi

# ── Move files ────────────────────────────────────────────────────────────────
MOVED=0
ERRORS=0
while IFS=$'\t' read -r SRC DEST_DIR NEW_NAME CATEGORY; do
    DEST_PATH="$DEST_DIR/$NEW_NAME"

    # Handle filename collision — append _1, _2, etc.
    if [[ -e "$DEST_PATH" ]]; then
        BASE="${NEW_NAME%.*}"
        EXT_PART="${NEW_NAME##*.}"
        N=1
        while [[ -e "$DEST_DIR/${BASE}_${N}.${EXT_PART}" ]]; do
            N=$(( N + 1 ))
        done
        DEST_PATH="$DEST_DIR/${BASE}_${N}.${EXT_PART}"
        NEW_NAME="${BASE}_${N}.${EXT_PART}"
    fi

    if mv "$SRC" "$DEST_PATH"; then
        echo "$DEST_PATH" >> "$MTIME_LIST"
        log "  -> [$CATEGORY] $(basename "$SRC") -> $NEW_NAME"
        MOVED=$(( MOVED + 1 ))
    else
        log "  ERROR: failed to move $(basename "$SRC") to $DEST_PATH"
        ERRORS=$(( ERRORS + 1 ))
    fi
done < "$MOVE_LIST"

# ── Set mtime ──────────────────────────────────────────────────────────────────
export _MTIME_LIST="$MTIME_LIST"

python3 <<'PYEOF'
import re, os
from datetime import datetime, timezone, timedelta

gmt_offset = int(os.environ['_GMT_OFFSET'])
ios_re = re.compile(r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(\d{3})_iOS\.\w+$')

with open(os.environ['_MTIME_LIST']) as f:
    paths = [line.rstrip('\n') for line in f if line.strip()]

for path in paths:
    m = ios_re.match(os.path.basename(path))
    if not m:
        continue
    Y,Mo,D,H,Mi,S,ms = m.groups()
    dt = datetime(int(Y),int(Mo),int(D),int(H),int(Mi),int(S),
                  int(ms)*1000, tzinfo=timezone(timedelta(hours=gmt_offset)))
    os.utime(path, (dt.timestamp(), dt.timestamp()))
PYEOF

# ── Summary ────────────────────────────────────────────────────────────────────
CAM_COUNT=$(find "$CAMERA_DIR"             -type f 2>/dev/null | wc -l || true)
SCR_COUNT=$(find "$SCREENSHOTS_DIR"        -type f 2>/dev/null | wc -l || true)
REC_COUNT=$(find "$SCREEN_RECORDINGS_DIR"  -type f 2>/dev/null | wc -l || true)
OTH_COUNT=$(find "$OTHERS_DIR"             -type f 2>/dev/null | wc -l || true)
log "Done. Moved: $MOVED | Errors: $ERRORS"
log "Totals — Camera: $CAM_COUNT | Screenshots: $SCR_COUNT | Screen Recordings: $REC_COUNT | Others: $OTH_COUNT"