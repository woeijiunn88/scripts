import sys
import http.cookiejar
from curl_cffi import requests

def load_netscape_cookies(cookie_file):
    cj = http.cookiejar.MozillaCookieJar(cookie_file)
    cj.load(ignore_discard=True, ignore_expires=True)
    cookies = {}
    for cookie in cj:
        cookies[cookie.name] = cookie.value
    return cookies

def main():
    cookie_file = "../../web-bot/cookies-melonbooks-co-jp.txt"
    try:
        cookies = load_netscape_cookies(cookie_file)
    except Exception as e:
        print(f"Error loading cookies: {e}")
        return

    url = "https://www.melonbooks.co.jp/detail/detail.php?product_id=3612748"
    
    print(f"Fetching {url} using curl_cffi for Akamai bypass...")
    
    # curl_cffi mimics a real browser TLS and HTTP/2 fingerprint
    session = requests.Session(impersonate="chrome")
    
    # Set cookies globally in the session
    for name, value in cookies.items():
        # curl_cffi expects (name, value, domain) or setting via headers
        session.cookies.set(name, value, domain=".melonbooks.co.jp")

    headers = {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Accept-Language": "en-US,en;q=0.9,ja;q=0.8",
        "Referer": "https://www.melonbooks.co.jp/",
    }
    
    try:
        response = session.get(url, headers=headers)
        response.raise_for_status()
        html = response.text
        
        print(f"Success! Status code: {response.status_code}")
        print(f"Content length: {len(html)} bytes")
        
        # Extract title to verify content
        import re
        title_match = re.search(r'<title>(.*?)</title>', html, re.IGNORECASE)
        if title_match:
            print(f"Page Title: {title_match.group(1).strip()}")
            
    except Exception as e:
        print(f"Request failed: {e}")

if __name__ == "__main__":
    main()
