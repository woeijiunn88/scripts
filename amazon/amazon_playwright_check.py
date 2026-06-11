import asyncio
import json
from pathlib import Path

from playwright.async_api import async_playwright


URL = "https://www.amazon.co.jp/dp/B0GYPFGB5Q"
AGE_CONFIRM = "https://www.amazon.co.jp/black-curtain/save-eligibility/black-curtain?returnUrl=%2Fdp%2FB0GYPFGB5Q"
PROXY = "socks5://127.0.0.1:1080"
COOKIE_FILE = Path("cookies-amazon-co-jp.txt")


def load_netscape_cookies(path: Path):
    cookies = []
    if not path.exists():
        return cookies
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 7:
            continue
        domain, _flag, cookie_path, secure, expires, name, value = parts
        cookie = {
            "name": name,
            "value": value,
            "domain": domain,
            "path": cookie_path or "/",
            "secure": secure.upper() == "TRUE",
            "httpOnly": False,
        }
        try:
            expiry = int(expires)
            if expiry > 0:
                cookie["expires"] = expiry
        except ValueError:
            pass
        cookies.append(cookie)
    return cookies


async def text_or_empty(page, selector):
    try:
        value = await page.locator(selector).first.text_content(timeout=2500)
        return " ".join(value.split()) if value else ""
    except Exception:
        return ""


async def collect_page(page):
    body = ""
    try:
        body = await page.locator("body").inner_text(timeout=5000)
    except Exception:
        pass
    nav_line = await text_or_empty(page, "#nav-link-accountList, #nav-link-accountList-nav-line-1")
    nav_full = await text_or_empty(page, "#nav-link-accountList")
    return {
        "final_url": page.url,
        "title": await page.title(),
        "product_title": await text_or_empty(page, "#productTitle"),
        "brand": await text_or_empty(page, "#bylineInfo"),
        "price": await text_or_empty(page, ".a-price .a-offscreen"),
        "availability": await text_or_empty(page, "#availability"),
        "feature_bullets": [
            " ".join(text.split())
            for text in await page.locator("#feature-bullets li span.a-list-item").all_text_contents()
            if text.strip()
        ][:8],
        "buybox": bool(await page.locator("#buybox, #desktop_buybox").count()),
        "adult_gate": "black-curtain" in page.url or "アダルトコンテンツ" in body,
        "captcha": bool(await page.locator("form[action*='validateCaptcha'], img[src*='captcha']").count()),
        "signin_page": "signin" in page.url or bool(await page.locator("#ap_email, input[name='email']").count()),
        "account_nav_present": bool(nav_line),
        "account_nav_text": nav_full or nav_line,
        "account_nav_signed_in": bool(
            nav_line
            and "ログイン" not in nav_line
            and "サインイン" not in nav_line
            and "sign in" not in nav_line.lower()
        ),
        "page_excerpt": " ".join(body.split())[:500],
    }


async def check_context(playwright, label, cookies=None):
    browser = await playwright.chromium.launch(
        headless=True,
        executable_path="/usr/bin/google-chrome-stable",
        proxy={"server": PROXY},
        args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-blink-features=AutomationControlled"],
    )
    context = await browser.new_context(
        locale="ja-JP",
        timezone_id="Asia/Tokyo",
        user_agent=(
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        ),
        viewport={"width": 1365, "height": 900},
    )
    if cookies:
        await context.add_cookies(cookies)
    page = await context.new_page()
    result = {"label": label, "proxy": PROXY, "cookie_count": len(cookies or [])}
    try:
        browser_cookies = await context.cookies("https://www.amazon.co.jp/")
        result["browser_cookie_names"] = sorted(cookie["name"] for cookie in browser_cookies)
        result["has_auth_cookie"] = any(
            cookie["name"] in {"at-acbjp", "sess-at-acbjp", "sst-acbjp", "x-acbjp"}
            for cookie in browser_cookies
        )
        response = await page.goto(URL, wait_until="domcontentloaded", timeout=45000)
        await page.wait_for_timeout(5000)
        result["initial_status"] = response.status if response else None
        result["initial"] = await collect_page(page)
        if result["initial"]["adult_gate"]:
            gate_response = await page.goto(AGE_CONFIRM, wait_until="domcontentloaded", timeout=45000)
            await page.wait_for_timeout(2000)
            final_response = await page.goto(URL, wait_until="domcontentloaded", timeout=45000)
            await page.wait_for_timeout(5000)
            result["age_confirm_status"] = gate_response.status if gate_response else None
            result["final_status"] = final_response.status if final_response else None
            result["final"] = await collect_page(page)
        else:
            result["final_status"] = result["initial_status"]
            result["final"] = result["initial"]
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        await browser.close()
    return result


async def main():
    cookies = load_netscape_cookies(COOKIE_FILE)
    async with async_playwright() as playwright:
        results = [
            await check_context(playwright, "no_cookies"),
            await check_context(playwright, "with_cookies", cookies),
        ]
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
