import sys, json, os, importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("bot", os.getcwd() + "/yt-monitor-bot.py")
bot = importlib.util.module_from_spec(spec)
sys.modules["bot"] = bot
spec.loader.exec_module(bot)

vid_id = "1EevjGF2nuU"
entry = bot.get_entry(vid_id)
if entry:
    msg_id = entry.get("telegram_message_id")
    if msg_id:
        print(f"Refreshing msg_id {msg_id} for {vid_id}...")
        text = bot.format_entry_message(entry)
        # For quality_pending, we use specific buttons if needed, or done buttons
        st = entry.get("status")
        if st == "quality_pending":
            kb = [] # No buttons while waiting for quality
        elif st in ("done", "done_upgraded"):
            kb = bot.kb_done_rd(vid_id, entry.get("url", ""))
        else:
            kb = bot.kb_pending(vid_id, entry.get("url", ""))
            
        bot.tg_edit_smart(msg_id, text, kb, entry)
        print("Done.")
    else:
        print("No msg_id found.")
else:
    print("Entry not found.")
