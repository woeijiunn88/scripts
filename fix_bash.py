import sys

with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-lib.sh", "r") as f:
    content = f.read()

# Modify tg_format_message to export TG_LAST_STATUS_LABEL and remove it from footer_line1
old_footer = """    local include_status=1
    local include_tech=1
    if [[ -n "${prompt_text//[$'\\n' ]/}" ]]; then
        include_status=0
        include_tech=0
    fi"""

# Wait, we want to strip HTML tags from status_line for the button
# at_ts might have <code>...</code>
export_logic = """
    # Export for tg_edit_smart to prepend as inline button
    export TG_LAST_STATUS_LABEL=$(echo "$status_line" | sed -E 's/<[^>]*>//g')
    
    local include_status=1
    local include_tech=1
    if [[ -n "${prompt_text//[$'\\n' ]/}" ]]; then
        include_status=0
        include_tech=0
    fi"""

content = content.replace(old_footer, export_logic)

old_build = """    # Build footer_line1: Duration | Resolution | Status
    local footer_line1=""
    local f1_parts=()
    [[ -n "$duration_str" ]] && f1_parts+=("$duration_str")
    [[ -n "$resolution" ]] && f1_parts+=("$resolution")
    if (( include_status )) && [[ -n "$status_line" ]]; then
        (( was_live )) && status_line+=" <i>(Livestream VOD)</i>"
        f1_parts+=("$status_line")
    fi"""

new_build = """    # Build footer_line1: Duration | Resolution (Status moved to inline button)
    local footer_line1=""
    local f1_parts=()
    [[ -n "$duration_str" ]] && f1_parts+=("$duration_str")
    [[ -n "$resolution" ]] && f1_parts+=("$resolution")"""
content = content.replace(old_build, new_build)

# Actually, the python side appends "(Livestream VOD)" to the status button if was_live!
# Let's add it to TG_LAST_STATUS_LABEL.
export_logic_with_vod = """
    if (( was_live )) && [[ "$status" != "fetch" && "$status" != "too_long" ]]; then
        status_line+=" (Livestream VOD)"
    fi
    export TG_LAST_STATUS_LABEL=$(echo "$status_line" | sed -E 's/<[^>]*>//g')

    local include_status=1
    local include_tech=1
    if [[ -n "${prompt_text//[$'\\n' ]/}" ]]; then
        include_tech=0
    fi"""
content = content.replace(export_logic, export_logic_with_vod)

# In tg_edit_smart, prepend the button
old_smart = """tg_edit_smart() {
    local msg_id="$1" text="$2" keyboard_json="${3:-}" entry_json="${4:-}"
    [[ -z "$msg_id" || "$msg_id" == "0" || "$msg_id" == "null" ]] && return 0
    local is_photo="false"
"""
new_smart = """tg_edit_smart() {
    local msg_id="$1" text="$2" keyboard_json="${3:-}" entry_json="${4:-}"
    [[ -z "$msg_id" || "$msg_id" == "0" || "$msg_id" == "null" ]] && return 0
    
    if [[ -n "$TG_LAST_STATUS_LABEL" && -n "$keyboard_json" ]]; then
        if [[ "$keyboard_json" == "[]" ]]; then
            keyboard_json=$(jq -n --arg st "$TG_LAST_STATUS_LABEL" '[[{"text":$st,"callback_data":"noop"}]]')
        else
            keyboard_json=$(echo "$keyboard_json" | jq -c --arg st "$TG_LAST_STATUS_LABEL" '[[{"text":$st,"callback_data":"noop"}]] + .')
        fi
    fi

    local is_photo="false"
"""
content = content.replace(old_smart, new_smart)

with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-lib.sh", "w") as f:
    f.write(content)

