# gemini

Scripts for managing and monitoring multiple Gemini CLI accounts.

## Scripts

| Script | Purpose |
|---|---|
| `gemini_quota_checker.sh` | Live quota dashboard — polls all accounts and displays remaining quota per model |
| `gemini_add_account.sh` | Add a new Gemini account to the multi-account setup |
| `gemini_del_account.sh` | Remove a Gemini account |

## Reference

- `gemini-multi-account.md` — setup guide for multi-account Gemini CLI configuration

## Requirements

- `gemini` CLI installed at `~/.npm-global/bin/gemini`
- `jq`
- Accounts configured under `~/.gemini/accounts/`

## Notes

- OAuth credentials live in `~/.gemini/accounts/<n>/oauth_creds.json` — not tracked in git
- `gemini_quota_checker.sh` polls all accounts found in `~/.gemini/accounts/` automatically
