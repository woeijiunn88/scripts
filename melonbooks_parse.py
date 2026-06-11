import sys
import http.cookiejar
from curl_cffi import requests
from bs4 import BeautifulSoup
import re

def load_netscape_cookies(cookie_file):
    cj = http.cookiejar.MozillaCookieJar(cookie_file)
    cj.load(ignore_discard=True, ignore_expires=True)
    cookies = {}
    for cookie in cj:
        cookies[cookie.name] = cookie.value
    return cookies

cookie_file = "web-bot/cookies-melonbooks-co-jp.txt"
try:
    cookies = load_netscape_cookies(cookie_file)
except Exception as e:
    print(f"Error loading cookies: {e}")
    sys.exit(1)

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
html_content = response.text
soup = BeautifulSoup(html_content, 'html.parser')

print("=== Melonbooks Product Extraction ===")

print("\n--- 1. Main Images ---")
images = []

# Method A: Look for <a> tags with data-size attribute (used by photoswipe/lightgallery)
for a in soup.find_all('a', attrs={'data-size': True}):
    href = a.get('href')
    if href and ('resize_image' in href or 'c_image' in href or 'image=' in href):
        if href.startswith('//'):
            href = 'https:' + href
        if href not in images:
            images.append(href)

# Method B: Regex on raw HTML if Method A fails (since JS might modify the DOM)
if not images:
    print("Method A failed, trying Regex on raw HTML...")
    # Looking for href="//melonbooks.akamaized.net/user_data/packages/resize_image.php?image=..."
    # without width/height
    pattern = r'href=["\'](//melonbooks\.akamaized\.net/user_data/packages/resize_image\.php\?image=[^&"\']+)[&"\']'
    matches = re.findall(pattern, html_content)
    for match in matches:
        href = 'https:' + match
        if href not in images:
            images.append(href)

for i, img in enumerate(images, 1):
    print(f"Image {i}: {img}")

print("\n--- 2. Main Info ---")
price_val = soup.select_one('p.price .price--value')
print(f"Price: ¥{price_val.text.strip() if price_val else 'N/A'}")

points_tag = soup.find('p', class_='point')
print(f"Points: {points_tag.text.strip() if points_tag else 'N/A'}")

release_date_tag = soup.find('span', class_='product-info__release-date')
print(f"Release Date: {release_date_tag.text.strip() if release_date_tag else 'N/A'}")

stock_tag = soup.find('span', class_='product-info__inventory-status__text')
print(f"Stock Status: {stock_tag.text.strip() if stock_tag else 'N/A'}")

print("\n--- 3. Comments & Details ---")
for h3 in soup.find_all('h3', class_='page-headline'):
    header_text = h3.text.strip()
    content_div = h3.find_next_sibling('div')
    if content_div:
        content_text = content_div.text.strip().replace('\n', ' ').replace('\r', '').replace('  ', ' ')
        print(f"[{header_text}]:\n{content_text}\n")

print("\n--- 4. Additional Info ---")
table_wrapper = soup.find('div', class_='table-wrapper')
if table_wrapper:
    table = table_wrapper.find('table')
    if table:
        for tr in table.find_all('tr'):
            th = tr.find('th')
            td = tr.find('td')
            if th and td:
                key = th.text.strip()
                val = td.text.strip().replace('\n', ' ').replace('\r', '')
                val = ' '.join(val.split())
                print(f"{key}: {val}")
