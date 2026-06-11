import sys, re

# REVERT BASH
with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-lib.sh", "r") as f:
    bash = f.read()

bash = re.sub(r'    # Export for tg_edit_smart to prepend as inline button.*?if \[\[ -n "\$\{prompt_text//\[\$\'\\n\' \]/}" \]\]; then\n        include_tech=0\n    fi',
"""    local include_status=1
    local include_tech=1
    if [[ -n "${prompt_text//[$'\\n' ]/}" ]]; then
        include_status=0
        include_tech=0
    fi""", bash, flags=re.DOTALL)

bash = bash.replace("""    # Build footer_line1: Duration | Resolution (Status moved to inline button)
    local footer_line1=""
    local f1_parts=()
    [[ -n "$duration_str" ]] && f1_parts+=("$duration_str")
    [[ -n "$resolution" ]] && f1_parts+=("$resolution")""",
"""    # Build footer_line1: Duration | Resolution | Status
    local footer_line1=""
    local f1_parts=()
    [[ -n "$duration_str" ]] && f1_parts+=("$duration_str")
    [[ -n "$resolution" ]] && f1_parts+=("$resolution")
    if (( include_status )) && [[ -n "$status_line" ]]; then
        (( was_live )) && status_line+=" <i>(Livestream VOD)</i>"
        f1_parts+=("$status_line")
    fi""")

bash = re.sub(r'tg_edit_smart\(\) \{\n    local msg_id="\$1" text="\$2" keyboard_json="\$\{3:-\}" entry_json="\$\{4:-\}"\n    \[\[ -z "\$msg_id" \|\| "\$msg_id" == "0" \|\| "\$msg_id" == "null" \]\] && return 0.*?\n    local is_photo="false"',
"""tg_edit_smart() {
    local msg_id="$1" text="$2" keyboard_json="${3:-}" entry_json="${4:-}"
    [[ -z "$msg_id" || "$msg_id" == "0" || "$msg_id" == "null" ]] && return 0
    local is_photo="false\"""", bash, flags=re.DOTALL)

with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-lib.sh", "w") as f:
    f.write(bash)

# REVERT PYTHON
with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-bot.py", "r") as f:
    py = f.read()

# 1. Remove get_status_label
py = re.sub(r'def get_status_label\(entry: dict, status_override: str = None\) -> str:.*?\n    return label\n\ndef format_entry_message\(', 'def format_entry_message(', py, flags=re.DOTALL)

# 2. Add label generation back
old_label = """
    # Line formatting: Label + Timestamp (if any)
    label = ""
    if status == "pending":
        label = "⏳ Queued"
    elif status == "premiere_pending":
        label = "🎬 Premiere"
    elif status == "live_pending":
        label = "🔴 Upcoming Live"
    elif status == "quality_pending":
        label = f"🚧 Done Pending{at_ts}"
    elif status == "downloading":
        label = "⬇️ Downloading…"
    elif status == "converting":
        label = "⏳ Converting…"
    elif status == "uploading":
        label = "📤 Uploading…"
    elif status in ("done", "done_upgraded"):
        suffix = " Premium" if status == "done_upgraded" else ""
        label = f"✅ Done{suffix}{at_ts}"
    elif status == "failed":
        label = f"❌ Failed{at_ts}"
    elif status == "skipped":
        label = "⏭️ Skipped"
    elif status == "cancelled":
        label = f"🚫 Cancelled{at_ts}"
    elif status == "delete_confirm":
        label = "⚠️ Confirm deletion?"
    elif status == "cancel_requested":
        label = "⏳ Cancelling"
    elif status in ("too_long", "fetch"):
        label = "📱 YouTube Short" if entry.get("is_short") else "📥 Fetched"
    else:
        label = status.capitalize()

    if status in ("premiere_pending", "live_pending"):
        sched_ts = entry.get("release_timestamp")
        if sched_ts:
            try:
                dt = datetime.fromtimestamp(sched_ts, timezone.utc).astimezone()
                sched_str = dt.strftime("%Y-%m-%d %H:%M")
                label += f" (Scheduled: <code>{sched_str}</code>)"
            except Exception:
                pass

    # ── Footer Assembly ──────────────────────────────────────────────────────"""

py = py.replace("# ── Footer Assembly ──────────────────────────────────────────────────────", old_label)

# 3. Restore footer lines
py = py.replace("""    footer_lines = []
    # Status label moved to inline keyboard button""", 
"""    footer_lines = []
    if include_status and not clean_extra:
        vod_tag = " <i>(Livestream VOD)</i>" if entry.get("was_live") else ""
        footer_lines.append(f"{label}{vod_tag}")""")

# 4. Remove add_status_btn and fix _classify_keyboard
py = re.sub(r'def _classify_keyboard\(entry: dict, st: str, vid_id: str, url: str\) -> list:.*?def add_status_btn', 'def _classify_keyboard(st: str, vid_id: str, url: str) -> list:\n    """Map a queue status string to the appropriate inline keyboard."""\n    if st in ("done", "done_upgraded", "quality_pending"):\n        return kb_done_rd(vid_id, url)\n    if st == "failed":\n        return kb_failed(vid_id, url)\n    if st == "pending":\n        return kb_pending(vid_id, url)\n    if st in ("too_long", "fetch"):\n        return kb_too_long(vid_id, url)\n    if st == "downloading":\n        return kb_downloading(vid_id)\n    if st == "cancel_requested":\n        return kb_cancel_requested()\n    if st == "skipped":\n        return kb_skipped(vid_id)\n    if st == "cancelled":\n        return kb_cancelled(vid_id)\n    if st in ("premiere_pending", "live_pending"):\n        return [[{"text": "Watch", "url": url, "style": "primary"}]]\n    # converting/uploading are transient display-only states — no persistent keyboard\n    return []\n\ndef add_status_btn', py, flags=re.DOTALL)

py = re.sub(r'def add_status_btn\(kb: list, entry: dict, status: str\) -> list:.*?def _kb_for_entry', 'def _kb_for_entry', py, flags=re.DOTALL)

# Fix calls to _classify_keyboard
py = py.replace("_classify_keyboard(entry, st, vid, url)", "_classify_keyboard(st, vid, url)")
py = py.replace("_classify_keyboard(info, status_override, vid_id, url)", "_classify_keyboard(status_override, vid_id, url)")
py = py.replace("_classify_keyboard(info, st, vid_id, url)", "_classify_keyboard(st, vid_id, url)")

with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-bot.py", "w") as f:
    f.write(py)

