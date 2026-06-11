import asyncio
import json
import re

from playwright.async_api import async_playwright


PROFILE = "/home/woeijiunn88/.config/google-chrome"
PROXY = "socks5://127.0.0.1:1080"
PRODUCT = "https://www.amazon.co.jp/dp/B0GYPFGB5Q"
AGE_CONFIRM = "https://www.amazon.co.jp/black-curtain/save-eligibility/black-curtain?returnUrl=%2Fdp%2FB0GYPFGB5Q"

PAGES = [
    ("home", "https://www.amazon.co.jp/"),
    ("product", PRODUCT),
    ("account_home", "https://www.amazon.co.jp/gp/css/homepage.html"),
    ("addresses", "https://www.amazon.co.jp/a/addresses"),
    ("content_devices", "https://www.amazon.co.jp/hz/mycd/myx"),
    ("yourstore_prefs", "https://www.amazon.co.jp/gp/yourstore/iyr/"),
]

KEYWORDS = ["アダルト", "成人", "年齢", "フィルター", "表示", "地域", "国", "住所", "ログイン", "サインイン"]


def redact(text):
    text = re.sub(r"[\w.+-]+@[\w.-]+", "[email]", text or "")
    text = re.sub(r"\b\d{3}-?\d{4}\b", "[postal]", text)
    text = re.sub(r"\b0\d{1,4}-?\d{1,4}-?\d{3,4}\b", "[phone]", text)
    return re.sub(r"\s+", " ", text).strip()[:800]


async def text_or_empty(page, selector):
    try:
        value = await page.locator(selector).first.text_content(timeout=2500)
        return " ".join(value.split()) if value else ""
    except Exception:
        return ""


async def inspect_page(page, label, url, handle_age_gate=False):
    result = {"label": label, "url": url}
    response = await page.goto(url, wait_until="domcontentloaded", timeout=45000)
    await page.wait_for_timeout(3500)
    body = ""
    try:
        body = await page.locator("body").inner_text(timeout=5000)
    except Exception:
        pass
    if handle_age_gate and ("black-curtain" in page.url or "アダルトコンテンツ" in body):
        gate = await page.goto(AGE_CONFIRM, wait_until="domcontentloaded", timeout=45000)
        await page.wait_for_timeout(1500)
        response = await page.goto(url, wait_until="domcontentloaded", timeout=45000)
        await page.wait_for_timeout(3500)
        try:
            body = await page.locator("body").inner_text(timeout=5000)
        except Exception:
            body = ""
        result["age_confirm_status"] = gate.status if gate else None
    nav = await text_or_empty(page, "#nav-link-accountList")
    result.update(
        {
            "status": response.status if response else None,
            "final_url": page.url,
            "title": await page.title(),
            "nav": redact(nav),
            "signed_in_nav": bool(nav and "ログイン" not in nav and "サインイン" not in nav),
            "product_title": await text_or_empty(page, "#productTitle"),
            "price": await text_or_empty(page, ".a-price .a-offscreen"),
            "availability": await text_or_empty(page, "#availability"),
            "signin_page": "signin" in page.url or bool(await page.locator("#ap_email, input[name='email']").count()),
            "not_found": "ページが見つかりません" in body or "何かお探しですか" in body,
            "adult_gate": "black-curtain" in page.url or "アダルトコンテンツ" in body,
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
    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            PROFILE,
            headless=True,
            executable_path="/usr/bin/google-chrome-stable",
            proxy={"server": PROXY},
            locale="ja-JP",
            timezone_id="Asia/Tokyo",
            viewport={"width": 1365, "height": 900},
            args=["--profile-directory=Default", "--no-sandbox", "--disable-dev-shm-usage"],
        )
        page = context.pages[0] if context.pages else await context.new_page()
        cookies = await context.cookies("https://www.amazon.co.jp/")
        results = {
            "profile": PROFILE,
            "proxy": PROXY,
            "amazon_cookie_names": sorted(cookie["name"] for cookie in cookies),
            "has_auth_cookie": any(cookie["name"] in {"at-acbjp", "sess-at-acbjp", "sst-acbjp"} for cookie in cookies),
            "pages": [],
        }
        for label, url in PAGES:
            results["pages"].append(await inspect_page(page, label, url, handle_age_gate=(label == "product")))
        await context.close()
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
