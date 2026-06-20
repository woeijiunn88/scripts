#!/usr/bin/env python3
"""
cookie_refresh.py
─────────────────
Headless Playwright cookie keep-alive for Twitter, Instagram, Facebook,
Bilibili, and Weibo. Visits each platform URL to reset session TTL
server-side, then exports fresh cookies to both config dirs.

Three-tier logic per platform:
  1. Load stored Playwright cookies → visit URL → if valid, save + export
  2. If expired: load Firefox cookies.sqlite → visit via Playwright → save + export
  3. If both fail: send Telegram admin alert

Usage:
  python3 cookie_refresh.py                    # refresh all platforms
  python3 cookie_refresh.py --platform twitter # refresh one platform
  python3 cookie_refresh.py --dry-run          # print status, no writes

Required env (loaded from notify-push .env):
  TELEGRAM_BOT_TOKEN
  TELEGRAM_DECISION_CHAT_ID
"""

import argparse, json, logging, os, shutil, sqlite3, sys, tempfile, time
from pathlib import Path
from dataclasses import dataclass, field

# ── Path setup ────────────────────────────────────────────────────────────────

_NOTIFY_PUSH_DIR = Path("/home/woeijiunn88/projects/notify-push")
if str(_NOTIFY_PUSH_DIR) not in sys.path:
    sys.path.insert(0, str(_NOTIFY_PUSH_DIR))

import notify_push_base as tg  # noqa: E402

NP_CFG     = Path(os.environ.get("NOTIFY_PUSH_CONFIG_DIR",    "~/.config/notify-push")).expanduser()
IMGFAV_CFG = Path(os.environ.get("IMG_FAV_CONFIG_DIR", "~/.config/img-fav-downloader")).expanduser()
PW_STORE   = NP_CFG / "playwright"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                    datefmt="%H:%M:%S", stream=sys.stdout)
log = logging.getLogger("cookie-refresh")

# ── Platform config ───────────────────────────────────────────────────────────

@dataclass
class Platform:
    label: str
    slug: str
    domains: list[str]
    url: str
    session_cookies: list[str]

PLATFORMS: list[Platform] = [
    Platform("Twitter",   "twitter",   [".twitter.com", ".x.com"],       "https://x.com/home",            ["auth_token"]),
    Platform("Instagram", "instagram", [".instagram.com"],                "https://www.instagram.com/",    ["sessionid"]),
    Platform("Facebook",  "facebook",  [".facebook.com"],                 "https://www.facebook.com/",     ["c_user", "xs"]),
    Platform("哔哩哔哩",  "bilibili",  [".bilibili.com"],                 "https://www.bilibili.com/",     ["SESSDATA", "bili_jct"]),
    Platform("Weibo",     "weibo",     [".weibo.com", ".weibo.cn", ".sina.com.cn"], "https://m.weibo.cn/", ["SUB"]),
]

PLATFORM_BY_SLUG  = {p.slug: p  for p in PLATFORMS}
PLATFORM_BY_LABEL = {p.label: p for p in PLATFORMS}

ALIASES: dict[str, str] = {
    "twitter": "twitter", "x": "twitter",
    "ig": "instagram", "insta": "instagram", "instagram": "instagram",
    "fb": "facebook", "facebook": "facebook",
    "bili": "bilibili", "bilibili": "bilibili", "哔哩哔哩": "bilibili",
    "weibo": "weibo",
}

# ── Result ────────────────────────────────────────────────────────────────────

@dataclass
class RefreshResult:
    label: str
    ok: bool
    source: str = ""      # "playwright", "firefox→playwright", ""
    cookie_count: int = 0
    error: str = ""

# ── Playwright helpers ────────────────────────────────────────────────────────

_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/148.0.0.0 Safari/537.36"
)


def _cookies_to_playwright(cookies: list[dict]) -> list[dict]:
    """Ensure cookies have the fields Playwright's add_cookies() requires."""
    out = []
    for c in cookies:
        entry = {
            "name":     c.get("name", ""),
            "value":    c.get("value", ""),
            "domain":   c.get("domain", ""),
            "path":     c.get("path", "/"),
            "secure":   bool(c.get("secure", False)),
            "httpOnly": bool(c.get("httpOnly", False)),
            "sameSite": c.get("sameSite", "None"),
        }
        exp = c.get("expires", -1)
        # Playwright requires -1 for session cookies; 0 is not valid
        entry["expires"] = float(exp) if exp and exp > 0 else -1
        out.append(entry)
    return out


def visit_with_playwright(url: str, cookies: list[dict],
                          session_cookie_names: list[str],
                          dry_run: bool = False) -> "tuple[bool, list[dict]]":
    """
    Load cookies into an isolated Chromium context, visit url,
    check session_cookie_names are present, return (valid, updated_cookies).
    """
    if dry_run:
        names = {c.get("name") for c in cookies}
        valid = all(n in names for n in session_cookie_names)
        return valid, cookies

    from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=True,
            args=["--disable-blink-features=AutomationControlled", "--no-sandbox"],
        )
        try:
            ctx = browser.new_context(
                viewport={"width": 1280, "height": 900},
                user_agent=_USER_AGENT,
                locale="en-US",
            )
            ctx.add_cookies(_cookies_to_playwright(cookies))
            page = ctx.new_page()
            try:
                page.goto(url, wait_until="domcontentloaded", timeout=30_000)
                time.sleep(2)
            except PWTimeout:
                log.warning(f"Page load timed out for {url} — checking cookies anyway")

            updated = ctx.cookies()
            cookie_map = {c["name"]: c["value"] for c in updated}
            valid = all(cookie_map.get(n) for n in session_cookie_names)
            return valid, updated
        finally:
            browser.close()


# ── Firefox import ────────────────────────────────────────────────────────────

def import_from_firefox(domains: list[str]) -> list[dict]:
    """Read matching cookies from Firefox's cookies.sqlite. Returns Playwright dicts."""
    profiles = sorted(
        Path.home().glob(".mozilla/firefox/*/cookies.sqlite"),
        key=lambda p: p.stat().st_mtime, reverse=True,
    )
    if not profiles:
        log.warning("No Firefox cookies.sqlite found")
        return []

    with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as f:
        tmp = Path(f.name)
    try:
        shutil.copy2(profiles[0], tmp)
        conn = sqlite3.connect(tmp)
        placeholders = ",".join("?" * len(domains))
        rows = conn.execute(
            f"SELECT host, path, isSecure, expiry, name, value, isHttpOnly "
            f"FROM moz_cookies WHERE host IN ({placeholders})",
            domains,
        ).fetchall()
        # Also query with LIKE for subdomains
        like_rows = []
        for d in domains:
            base = d.lstrip(".")
            like_rows += conn.execute(
                "SELECT host, path, isSecure, expiry, name, value, isHttpOnly "
                "FROM moz_cookies WHERE host LIKE ?",
                (f"%{base}",),
            ).fetchall()
        conn.close()
        all_rows = {(r[4], r[0]): r for r in rows + like_rows}.values()  # dedup by name+host
    finally:
        tmp.unlink(missing_ok=True)

    cookies = []
    for host, path_, secure, expiry, name, value, http_only in all_rows:
        cookies.append({
            "name":     name,
            "value":    value,
            "domain":   host,
            "path":     path_,
            "secure":   bool(secure),
            "httpOnly": bool(http_only),
            # Firefox stores expiry in seconds; values > 1e10 are milliseconds (old profiles)
            "expires":  float(expiry / 1000 if expiry and expiry > 1e10 else expiry) if expiry and expiry > 0 else -1,
            "sameSite": "None",
        })
    log.info(f"  Firefox: imported {len(cookies)} cookies from {profiles[0]}")
    return cookies


# ── Cookie store I/O ──────────────────────────────────────────────────────────

def load_playwright_store(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        return json.loads(path.read_text())
    except Exception as e:
        log.warning(f"Failed to read Playwright store {path}: {e}")
        return []


def save_playwright_store(path: Path, cookies: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(cookies, indent=2))
    tmp.replace(path)


def write_netscape(path: Path, cookies: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# Netscape HTTP Cookie File"]
    for c in cookies:
        domain = c.get("domain", "")
        inc_sub = "TRUE" if domain.startswith(".") else "FALSE"
        secure  = "TRUE" if c.get("secure") else "FALSE"
        expiry  = int(c.get("expires") or 0)
        name    = c.get("name", "")
        value   = c.get("value", "")
        path_   = c.get("path", "/")
        lines.append(f"{domain}\t{inc_sub}\t{path_}\t{secure}\t{expiry}\t{name}\t{value}")
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(path)


# ── Per-platform refresh ──────────────────────────────────────────────────────

def refresh_platform(plat: Platform, dry_run: bool = False) -> RefreshResult:
    pw_store     = PW_STORE / f"{plat.slug}.json"
    netscape_np  = NP_CFG     / "cookies" / f"{plat.slug}.txt"
    netscape_img = IMGFAV_CFG / "cookies" / f"{plat.slug}.txt"

    log.info(f"[{plat.label}] Starting refresh")

    # Step 1: try Playwright store
    source = "playwright"
    stored = load_playwright_store(pw_store)
    if stored:
        log.info(f"[{plat.label}] Trying Playwright store ({len(stored)} cookies)")
        ok, updated = visit_with_playwright(plat.url, stored, plat.session_cookies, dry_run)
    else:
        log.info(f"[{plat.label}] No Playwright store — going straight to Firefox")
        ok, updated = False, []

    # Step 2: Firefox as cookie source if Playwright cookies expired/missing
    if not ok:
        log.info(f"[{plat.label}] Playwright session invalid — trying Firefox cookies.sqlite")
        firefox_cookies = import_from_firefox(plat.domains)
        if firefox_cookies:
            source = "firefox→playwright"
            ok, updated = visit_with_playwright(plat.url, firefox_cookies, plat.session_cookies, dry_run)
        else:
            log.warning(f"[{plat.label}] Firefox also has no cookies")

    if not ok:
        log.error(f"[{plat.label}] Both Playwright and Firefox failed")
        return RefreshResult(label=plat.label, ok=False,
                             error="Playwright + Firefox both failed — re-login required")

    log.info(f"[{plat.label}] Session valid via {source} ({len(updated)} cookies)")

    if not dry_run:
        save_playwright_store(pw_store, updated)
        write_netscape(netscape_np, updated)
        write_netscape(netscape_img, updated)
        log.info(f"[{plat.label}] Exported to {netscape_np} and {netscape_img}")

    return RefreshResult(label=plat.label, ok=True, source=source, cookie_count=len(updated))


# ── Telegram reporting ────────────────────────────────────────────────────────

_PREV_FAILED: set[str] = set()  # track labels that were failing (for recovery messages)


def _send_summary(results: list[RefreshResult], dry_run: bool) -> None:
    if dry_run:
        return

    failed  = [r for r in results if not r.ok]
    success = [r for r in results if r.ok]

    lines = []
    for r in results:
        safe = tg.esc(tg._anti_link(r.label))
        if r.ok:
            lines.append(f"• {safe} [{tg.esc(r.source)}]: {r.cookie_count} cookies")
        else:
            lines.append(f"• {safe}: ❌ {tg.esc(r.error)}")

    if failed:
        header = "⚠️ <b>Cookie refresh — action required</b>"
        footer_parts = []
        for r in failed:
            slug = PLATFORM_BY_LABEL[r.label].slug
            footer_parts.append(f"Re-login to <b>{tg.esc(tg._anti_link(r.label))}</b> in Firefox, then run: <code>/cookies refresh {slug}</code>")
        body = header + "\n\n" + "\n".join(lines) + "\n\n" + "\n".join(footer_parts)
    else:
        body = "✅ <b>Cookie refresh complete</b>\n\n" + "\n".join(lines)

    tg._tg_post("sendMessage", json={
        "chat_id":                  tg.CHAT_ID,
        "text":                     body,
        "parse_mode":               "HTML",
        "disable_web_page_preview": True,
    })

    # Per-platform admin alerts and recovery messages
    for r in results:
        safe = tg.esc(tg._anti_link(r.label))
        slug = PLATFORM_BY_LABEL[r.label].slug
        if not r.ok:
            _PREV_FAILED.add(slug)
            tg.notify_admin(
                f"{r.label} session expired — Playwright and Firefox cookies both invalid. "
                f"Re-login in Firefox browser.",
                error_class=f"cookie-refresh-{slug}",
            )
        elif slug in _PREV_FAILED:
            _PREV_FAILED.discard(slug)
            tg.clear_admin_error()
            tg._tg_post("sendMessage", json={
                "chat_id":    tg.CHAT_ID,
                "text":       f"✅ <b>{safe}</b> cookies recovered ({tg.esc(r.source)})",
                "parse_mode": "HTML",
            })


# ── JSON output (for /cookies refresh integration) ───────────────────────────

def _print_json(results: list[RefreshResult]) -> None:
    out = []
    for r in results:
        out.append({
            "label":        r.label,
            "ok":           r.ok,
            "source":       r.source,
            "cookie_count": r.cookie_count,
            "error":        r.error,
        })
    print(json.dumps(out))


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description="Playwright cookie keep-alive refresh")
    parser.add_argument("--platform", metavar="PLATFORM",
                        help="Refresh one platform (slug or alias: twitter, ig, fb, bili, weibo)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print status without writing files or sending Telegram messages")
    parser.add_argument("--json", action="store_true",
                        help="Output JSON result to stdout (for bot integration)")
    args = parser.parse_args()

    # Resolve target platforms
    if args.platform:
        slug = ALIASES.get(args.platform.lower())
        if not slug or slug not in PLATFORM_BY_SLUG:
            print(f"Unknown platform: {args.platform}. "
                  f"Valid: {', '.join(sorted(ALIASES))}", file=sys.stderr)
            return 1
        targets = [PLATFORM_BY_SLUG[slug]]
    else:
        targets = PLATFORMS

    results = []
    for plat in targets:
        try:
            result = refresh_platform(plat, dry_run=args.dry_run)
        except Exception as e:
            log.error(f"[{plat.label}] Unexpected error: {e}")
            result = RefreshResult(label=plat.label, ok=False, error=str(e)[:200])
        results.append(result)

    if args.dry_run:
        for r in results:
            status = f"OK [{r.source}]" if r.ok else f"FAILED: {r.error}"
            print(f"  {r.label}: {status}")
        return 0

    if args.json:
        _print_json(results)
    else:
        _send_summary(results, dry_run=False)

    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
