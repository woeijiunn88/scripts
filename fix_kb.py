import sys

with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-bot.py", "r") as f:
    content = f.read()

import re
old = """    # converting/uploading are transient display-only states — no persistent keyboard
    kb = []"""
new = """    # converting/uploading are transient display-only states — no persistent keyboard
    if kb is None:
        kb = []"""
content = content.replace(old, new)

# Actually, I should initialize kb = None at the top of _classify_keyboard
old_top = """def _classify_keyboard(entry: dict, st: str, vid_id: str, url: str) -> list:
    \"\"\"Map a queue status string to the appropriate inline keyboard.\"\"\"
    if st in ("done", "done_upgraded", "quality_pending"):"""
new_top = """def _classify_keyboard(entry: dict, st: str, vid_id: str, url: str) -> list:
    \"\"\"Map a queue status string to the appropriate inline keyboard.\"\"\"
    kb = None
    if st in ("done", "done_upgraded", "quality_pending"):"""
content = content.replace(old_top, new_top)

with open("/home/woeijiunn88/workspace/yt-dlp-script/yt-monitor-bot.py", "w") as f:
    f.write(content)
