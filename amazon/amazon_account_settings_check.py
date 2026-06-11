import asyncio
import http.cookiejar
import json
import re
from pathlib import Path

from playwright.async_api import async_playwright


COOKIE_FILE = Path("cookies-amazon-co-jp.txt")
PROXY = "socks5://127.0.0.1:1080"

PAGES = [
    ("home", "https://www.amazon.co.jp/"),
    ("product", "https://www.amazon.co.jp/dp/B0GYPFGB5Q"),
    ("account_home", "https://www.amazon.co.jp/gp/css/homepage.html"),
    ("addresses", "https://www.amazon.co.jp/a/addresses"),
    ("content_devices", "https://www.amazon.co.jp/hz/mycd/myx"),
    ("yourstore_prefs", "https://www.amazon.co.jp/gp/yourstore/iyr/"),
]

KEYWORDS = [
    "アダルト",
    "成人",
    "年齢",
    "フィルター",
    "表示",
    "地域",
    "国",
    "住所",
    "ログイン",
    "サインイン",
]


def load_cookies(path: Path):
    jar = http.cookiejar.MozillaCookieJar(path)
    jar.load(ignore_discard=True, ignore_expires=True)
    return [
        {
            "name": c.name,
            "value": c.value,
            "domain": c.domain,
            "path": c.path,
            "secure": bool(c.secure),
            "httpOnly": False,
        }
        for c in jar
    ]


def redact(text: str):
    text = re.sub(r"[\w.+-]+@[\w.-]+", "[email]", text)
    text = re.sub(r"\b\d{3}-?\d{4}\b", "[postal]", text)
    text = re.sub(r"\b0\d{1,4}-?\d{1,4}-?\d{3,4}\b", "[phone]", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:800]


async def text_or_empty(page, selector):
    try:
        value = await page.locator(selector).first.text_content(timeout=2500)
        return " ".join(value.split()) if value else ""
    except Exception:
        return ""


async def inspect_page(page, label, url):
    result = {"label": label, "url": url}
    response = await page.goto(url, wait_until="domcontentloaded", timeout=45000)
    await page.wait_for_timeout(3500)
    body = ""
    try:
        body = await page.locator("body").inner_text(timeout=5000)
    except Exception:
        pass
    nav = await text_or_empty(page, "#nav-link-accountList")
    result.update(
        {
            "status": response.status if response else None,
            "final_url": page.url,
            "title": await page.title(),
            "nav": redact(nav),
            "signed_in_nav": bool(nav and "ログイン" not in nav and "サインイン" not in nav),
            "signin_page": "signin" in page.url or bool(await page.locator("#ap_email, input[name='email']").count()),
            "not_found": "ページが見つかりません" in body or "何かお探しですか" in body,
            "keyword_lines": [],
        }
    )
    lines = []
    for line in body.splitlines():
        clean = " ".join(line.split())
        if clean and any(keyword in clean for keyword in KEYWORDS):
            lines.append(redact(clean))
    result["keyword_lines"] = lines[:25]
    return result


async def main():
    cookies = load_cookies(COOKIE_FILE)
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            executable_path="/usr/bin/google-chrome-stable",
            proxy={"server": PROXY},
            args=["--no-sandbox", "--disable-dev-shm-usage"],
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
        await context.add_cookies(cookies)
        page = await context.new_page()
        results = [await inspect_page(page, label, url) for label, url in PAGES]
        await browser.close()
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
