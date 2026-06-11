import asyncio
import json
import re

from playwright.async_api import async_playwright


PROFILE = "/home/woeijiunn88/.config/google-chrome"
PROXY = "socks5://127.0.0.1:1080"
PRODUCT = "https://www.amazon.co.jp/dp/B0GYPFGB5Q"
AGE_CONFIRM = "https://www.amazon.co.jp/black-curtain/save-eligibility/black-curtain?returnUrl=%2Fdp%2FB0GYPFGB5Q"


def redact(text):
    text = re.sub(r"[\w.+-]+@[\w.-]+", "[email]", text or "")
    text = re.sub(r"\b\d{3}-?\d{4}\b", "[postal]", text)
    return re.sub(r"\s+", " ", text).strip()[:500]


async def body_text(page):
    try:
        return await page.locator("body").inner_text(timeout=4000)
    except Exception:
        return ""


async def nav_text(page):
    try:
        value = await page.locator("#nav-link-accountList").first.text_content(timeout=3000)
        return redact(value)
    except Exception:
        return ""


async def snapshot(page, response):
    body = await body_text(page)
    title = ""
    try:
        title = await page.locator("#productTitle").first.text_content(timeout=2500)
    except Exception:
        pass
    return {
        "status": response.status if response else None,
        "url": page.url,
        "page_title": await page.title(),
        "nav": await nav_text(page),
        "signed_in_nav": bool((await nav_text(page)) and "ログイン" not in (await nav_text(page)) and "サインイン" not in (await nav_text(page))),
        "product_title": redact(title),
        "not_found": "ページが見つかりません" in body or "何かお探しですか" in body,
        "adult_gate": "black-curtain" in page.url or "アダルトコンテンツ" in body,
        "excerpt": redact(body),
    }


async def main():
    result = {"profile": PROFILE, "proxy": PROXY, "steps": []}
    async with async_playwright() as p:
        print("launching profile", flush=True)
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
        result["amazon_cookie_names"] = sorted(cookie["name"] for cookie in cookies)
        result["has_auth_cookie"] = any(cookie["name"] in {"at-acbjp", "sess-at-acbjp", "sst-acbjp"} for cookie in cookies)

        print("opening home", flush=True)
        r = await page.goto("https://www.amazon.co.jp/", wait_until="domcontentloaded", timeout=20000)
        await page.wait_for_timeout(2500)
        result["steps"].append({"label": "home", **await snapshot(page, r)})

        print("opening product", flush=True)
        r = await page.goto(PRODUCT, wait_until="domcontentloaded", timeout=20000)
        await page.wait_for_timeout(2500)
        first = await snapshot(page, r)
        result["steps"].append({"label": "product_initial", **first})

        if first["adult_gate"]:
            print("confirming age gate", flush=True)
            gate = await page.goto(AGE_CONFIRM, wait_until="domcontentloaded", timeout=20000)
            await page.wait_for_timeout(1500)
            r = await page.goto(PRODUCT, wait_until="domcontentloaded", timeout=20000)
            await page.wait_for_timeout(2500)
            result["steps"].append({"label": "product_after_age_gate", "age_confirm_status": gate.status if gate else None, **await snapshot(page, r)})

        await context.close()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
