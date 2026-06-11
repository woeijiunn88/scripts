import asyncio
import json
import os
import re
import subprocess
import sys
import time
from urllib.request import urlopen

from playwright.async_api import async_playwright


PROXY = "socks5://127.0.0.1:1080"
PRODUCT = "https://www.amazon.co.jp/dp/B0GYPFGB5Q"
AGE_CONFIRM = "https://www.amazon.co.jp/black-curtain/save-eligibility/black-curtain?returnUrl=%2Fdp%2FB0GYPFGB5Q"


def redact(text):
    text = re.sub(r"[\w.+-]+@[\w.-]+", "[email]", text or "")
    text = re.sub(r"\b\d{3}-?\d{4}\b", "[postal]", text)
    return re.sub(r"\s+", " ", text).strip()[:800]


async def text_or_empty(page, selector):
    try:
        value = await page.locator(selector).first.text_content(timeout=2500)
        return " ".join(value.split()) if value else ""
    except Exception:
        return ""


async def snapshot(page, response):
    body = ""
    try:
        body = await page.locator("body").inner_text(timeout=5000)
    except Exception:
        pass
    nav = await text_or_empty(page, "#nav-link-accountList")
    return {
        "status": response.status if response else None,
        "url": page.url,
        "page_title": await page.title(),
        "nav": redact(nav),
        "signed_in_nav": bool(nav and "ログイン" not in nav and "サインイン" not in nav),
        "product_title": redact(await text_or_empty(page, "#productTitle")),
        "price": await text_or_empty(page, ".a-price .a-offscreen"),
        "availability": await text_or_empty(page, "#availability"),
        "not_found": "ページが見つかりません" in body or "何かお探しですか" in body,
        "adult_gate": "black-curtain" in page.url or "アダルトコンテンツ" in body,
        "signin_page": "signin" in page.url or bool(await page.locator("#ap_email, input[name='email']").count()),
        "excerpt": redact(body),
    }


def wait_for_cdp(port):
    url = f"http://127.0.0.1:{port}/json/version"
    for _ in range(80):
        try:
            with urlopen(url, timeout=0.5) as response:
                return json.loads(response.read().decode())
        except Exception:
            time.sleep(0.25)
    raise TimeoutError("Chrome DevTools endpoint did not start")


async def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 amazon_cdp_profile_check.py /tmp/chrome-profile-copy")
    profile = sys.argv[1]
    port = 9223
    chrome = subprocess.Popen(
        [
            "/usr/bin/google-chrome-stable",
            "--headless=new",
            f"--remote-debugging-port={port}",
            f"--user-data-dir={profile}",
            "--profile-directory=Default",
            f"--proxy-server={PROXY}",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    result = {"profile_copy": profile, "proxy": PROXY, "steps": []}
    try:
        version = wait_for_cdp(port)
        result["browser"] = version.get("Browser")
        async with async_playwright() as p:
            browser = await p.chromium.connect_over_cdp(f"http://127.0.0.1:{port}")
            context = browser.contexts[0]
            page = context.pages[0] if context.pages else await context.new_page()
            cookies = await context.cookies("https://www.amazon.co.jp/")
            result["amazon_cookie_names"] = sorted(cookie["name"] for cookie in cookies)
            result["has_auth_cookie"] = any(cookie["name"] in {"at-acbjp", "sess-at-acbjp", "sst-acbjp"} for cookie in cookies)

            r = await page.goto("https://www.amazon.co.jp/", wait_until="domcontentloaded", timeout=30000)
            await page.wait_for_timeout(3000)
            result["steps"].append({"label": "home", **await snapshot(page, r)})

            r = await page.goto(PRODUCT, wait_until="domcontentloaded", timeout=30000)
            await page.wait_for_timeout(3000)
            first = await snapshot(page, r)
            result["steps"].append({"label": "product_initial", **first})

            if first["adult_gate"]:
                gate = await page.goto(AGE_CONFIRM, wait_until="domcontentloaded", timeout=30000)
                await page.wait_for_timeout(1500)
                r = await page.goto(PRODUCT, wait_until="domcontentloaded", timeout=30000)
                await page.wait_for_timeout(3000)
                result["steps"].append({"label": "product_after_age_gate", "age_confirm_status": gate.status if gate else None, **await snapshot(page, r)})

            await browser.close()
    finally:
        chrome.terminate()
        try:
            chrome.wait(timeout=10)
        except subprocess.TimeoutExpired:
            chrome.kill()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
