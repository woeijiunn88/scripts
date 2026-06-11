# amazon

Playwright-based diagnostic scripts for checking Amazon JP account state — specifically adult content filter visibility and age verification settings.

## Scripts

| Script | Method | Purpose |
|---|---|---|
| `amazon_account_settings_check.py` | Cookie file + proxy | Checks account/address pages for adult filter keywords |
| `amazon_cdp_profile_check.py` | CDP attach to running Chrome | Checks age confirmation via Chrome DevTools Protocol |
| `amazon_chrome_profile_check.py` | Chrome profile reuse | Full page check using existing Chrome profile |
| `amazon_chrome_profile_quick.py` | Chrome profile reuse | Quick nav-bar only check |
| `amazon_playwright_check.py` | Cookie file + proxy | Minimal age confirmation check |

## Requirements

```bash
pip install playwright
playwright install chromium
```

## Notes

- Proxy: `socks5://127.0.0.1:1080` hardcoded in all scripts
- Cookie file: `cookies-amazon-co-jp.txt` (Netscape format) — not tracked in git
- Chrome profile: `~/.config/google-chrome` used by profile-based scripts
- All scripts redact PII (email, postal code, phone) before printing output
