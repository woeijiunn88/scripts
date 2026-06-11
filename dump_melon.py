import http.cookiejar
from curl_cffi import requests
import os

def load_netscape_cookies(cookie_file):
    cj = http.cookiejar.MozillaCookieJar(cookie_file)
    cj.load(ignore_discard=True, ignore_expires=True)
    cookies = {}
    for cookie in cj:
        cookies[cookie.name] = cookie.value
    return cookies

cookie_file = "web-bot/cookies-melonbooks-co-jp.txt"
cookies = load_netscape_cookies(cookie_file)
url = "https://www.melonbooks.co.jp/detail/detail.php?product_id=3612748"

session = requests.Session(impersonate="chrome")
for name, value in cookies.items():
    session.cookies.set(name, value, domain=".melonbooks.co.jp")

headers = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,ja;q=0.8",
    "Referer": "https://www.melonbooks.co.jp/",
}

response = session.get(url, headers=headers)
os.makedirs(".gemini/tmp", exist_ok=True)
with open(".gemini/tmp/melonbooks_raw.html", "w") as f:
    f.write(response.text)
print("Dumped to .gemini/tmp/melonbooks_raw.html")
