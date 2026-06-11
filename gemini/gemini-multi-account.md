# Gemini CLI Multi-Account Setup

## Overview

Seven isolated Gemini CLI accounts (g1–g7) running under a single Linux user,
each with its own OAuth session and quota. A `gquota` script checks remaining
quota across all accounts in parallel.

---

## Directory Layout

```
~/.gemini/accounts/
├── g1/
│   └── .gemini/
│       ├── oauth_creds.json       # access_token, refresh_token, expiry_date
│       ├── settings.json          # auth type, model, session retention, etc.
│       ├── google_accounts.json
│       ├── projects.json
│       ├── state.json
│       ├── trustedFolders.json
│       ├── installation_id
│       ├── history/
│       └── tmp/
├── g2/ … g7/                      # same structure
```

`~/.npm-global/bin/gemini` → actual CLI binary (installed without sudo via npm global).

---

## How Account Isolation Works

The Gemini CLI (v0.40.1+) determines its config directory with this logic
(from `chunk-F73F75XM.js`):

```js
var GEMINI_DIR = ".gemini";

function homedir() {
  const envHome = process.env["GEMINI_CLI_HOME"];
  if (envHome) return envHome;   // treat as HOME replacement
  return os.homedir();
}

// config dir = homedir() + "/.gemini"
```

**Key point:** `GEMINI_CLI_HOME` is a **HOME directory replacement**, not a
direct path to the `.gemini` dir. The CLI always appends `.gemini` itself.

| Env var | Purpose | Correct value for g2 |
|---|---|---|
| `HOME` | Standard Unix home | `~/.gemini/accounts/g2` |
| `GEMINI_CLI_HOME` | Home replacement for CLI | `~/.gemini/accounts/g2` (same as HOME) |
| `GEMINI_HOME` | Unused by the CLI | set for clarity only |

Setting `GEMINI_CLI_HOME` to the `.gemini` subdir (e.g. `…/g2/.gemini`) causes
a double-`.gemini` path (`…/g2/.gemini/.gemini/`) and breaks auth.

---

## ~/.bashrc Aliases

```bash
# Default account (uses real home)
alias gemini='HOME="/home/woeijiunn88" GEMINI_HOME="/home/woeijiunn88/.gemini" gemini'

# Per-account switchers
alias g1="HOME=\"/home/woeijiunn88/.gemini/accounts/g1\" GEMINI_HOME=\"/home/woeijiunn88/.gemini/accounts/g1/.gemini\" GEMINI_CLI_HOME=\"/home/woeijiunn88/.gemini/accounts/g1\" gemini"
alias g2="HOME=\"/home/woeijiunn88/.gemini/accounts/g2\" GEMINI_HOME=\"/home/woeijiunn88/.gemini/accounts/g2/.gemini\" GEMINI_CLI_HOME=\"/home/woeijiunn88/.gemini/accounts/g2\" gemini"
# … g3–g7 follow the same pattern

alias gquota='/home/woeijiunn88/gquota'
```

---

## gquota Script (`~/gquota`)

Checks flash and pro quota for every account in parallel with a live-updating
terminal display.

### Key variables

```bash
REAL_USER_HOME="/home/woeijiunn88"
GEMINI_BIN="/home/woeijiunn88/.npm-global/bin/gemini"   # must be absolute, not /usr/bin/gemini
ENDPOINT="https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
ACCOUNTS=$(ls -1 "$REAL_USER_HOME/.gemini/accounts/" | sort -V)
```

### Per-account flow

1. Read `oauth_creds.json` from `~/.gemini/accounts/<acc>/.gemini/`.
2. Create an isolated tmp home `$TMP_DIR/home_<acc>/` and symlink all config
   files from the real account into `$TMP_DIR/home_<acc>/.gemini/`.
3. Run a silent ping to refresh the access token:
   ```bash
   timeout 10s env \
     HOME="$REAL_USER_HOME" \
     GEMINI_CLI_HOME="$PING_HOME" \        # PING_HOME, not PING_HOME/.gemini
     "$GEMINI_BIN" --skip-trust -m "gemini-3-flash-preview" -p "ping" \
     > /dev/null 2>&1
   ```
   `GEMINI_CLI_HOME="$PING_HOME"` → CLI resolves config at `$PING_HOME/.gemini/` ✓
4. If the CLI replaced a symlink with a real file, copy it back to the real
   `oauth_creds.json`.
5. Call the quota API with the `access_token` from the (now refreshed) creds.

### Common errors and causes

| Display | Cause |
|---|---|
| `[AUTH ERR]` | `access_token` expired and silent refresh failed |
| `[TOKEN ERR]` | `access_token` field missing from creds file |
| `[NO CRED]` | `oauth_creds.json` not found for that account |
| `[API ERR]` | Quota endpoint returned empty/invalid JSON |

---

## Known Pitfalls

### 1. Wrong `GEMINI_BIN` path
The npm-global binary is **not** at `/usr/bin/gemini`. It lives at:
```
/home/woeijiunn88/.npm-global/bin/gemini
```
Using the wrong path causes the silent refresh ping to silently fail (exit 127),
so all tokens expire and every account shows `[AUTH ERR]`.

### 2. `GEMINI_CLI_HOME` must point to the HOME dir, not the `.gemini` dir
The CLI **appends** `.gemini` to `GEMINI_CLI_HOME`. If you pass the `.gemini`
subdir, you get a double-`.gemini` path and the CLI cannot find `settings.json`
or `oauth_creds.json`, producing:
```
Please set an Auth method in your …/.gemini/.gemini/settings.json
```

### 3. Adding a new account (g8, g9, …)

```bash
# 1. Create dirs
mkdir -p ~/.gemini/accounts/g8/.gemini

# 2. Log in with the new account
HOME="$HOME/.gemini/accounts/g8" \
GEMINI_CLI_HOME="$HOME/.gemini/accounts/g8" \
gemini   # complete OAuth flow in browser

# 3. Add alias to ~/.bashrc (copy g7 pattern, change g7→g8)

# 4. source ~/.bashrc
```

---

## Manual Token Refresh

If tokens expire and gquota cannot refresh them automatically:

```bash
GEMINI_BIN="/home/woeijiunn88/.npm-global/bin/gemini"

# Refresh a single account
timeout 30s env \
  HOME="/home/woeijiunn88" \
  GEMINI_CLI_HOME="/home/woeijiunn88/.gemini/accounts/g2" \
  "$GEMINI_BIN" --skip-trust -m "gemini-2.5-flash" -p "ping"

# Refresh all expired accounts in parallel
for d in g1 g2 g3 g4 g5 g6 g7; do
  (timeout 30s env \
    HOME="/home/woeijiunn88" \
    GEMINI_CLI_HOME="/home/woeijiunn88/.gemini/accounts/$d" \
    "$GEMINI_BIN" --skip-trust -m "gemini-2.5-flash" -p "ping" \
    > /dev/null 2>&1 && echo "$d: ok") &
done
wait
```

### Check token expiry without running gquota

```bash
NOW=$(date +%s%3N)
for d in g1 g2 g3 g4 g5 g6 g7; do
  expiry=$(jq -r '.expiry_date // 0' \
    "/home/woeijiunn88/.gemini/accounts/$d/.gemini/oauth_creds.json")
  [ "$expiry" -gt "$NOW" ] \
    && echo "$d: VALID ($(( (expiry - NOW) / 60000 ))min left)" \
    || echo "$d: EXPIRED"
done
```
