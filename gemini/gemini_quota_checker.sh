#!/bin/bash
# Gemini CLI Quota Checker (Robust V2)

REAL_USER_HOME="/home/woeijiunn88"
ENDPOINT="https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
GEMINI_BIN="/home/woeijiunn88/.npm-global/bin/gemini"

# ANSI Definitions
C_POLL="\e[2m"
C_GRN="\e[32m"
C_BGRN="\e[92m"
C_YLW="\e[33m"
C_BYLW="\e[93m"
C_RED="\e[31m"
C_BRED="\e[91m"
C_OFF="\e[90m"
C_ERR="\e[91m"
C_RST="\e[0m"

# Track temp files for buffered output
TMP_DIR=$(mktemp -d /tmp/gquota.XXXXXX)

cleanup() {
    # Remove our internal temp files
    rm -rf "$TMP_DIR" 2>/dev/null
    tput cnorm
}
trap cleanup EXIT SIGINT SIGTERM

ACCOUNTS=$(ls -1 "$REAL_USER_HOME/.gemini/accounts/" 2>/dev/null | sort -V)
NUM_ACCOUNTS=$(echo "$ACCOUNTS" | wc -l)

# Hide cursor
tput civis

# Header
printf "%-4s | %-18s | %-18s\n" "Acc" "Flash (3)" "Pro (3.1)"
echo "----------------------------------------------"

# Initial "POLLING" display
for ACC in $ACCOUNTS; do
    printf "%-4s | %b[%s]%b            | %b[%s]%b\n" "$ACC" "$C_POLL" "WAIT" "$C_RST" "$C_POLL" "WAIT" "$C_RST"
done

check_account_quota() {
    local ACCOUNT_NAME=$1
    local OUT_FILE="$TMP_DIR/$ACCOUNT_NAME"
    
    local ACCOUNT_HOME="$REAL_USER_HOME/.gemini/accounts/$ACCOUNT_NAME"
    local CRED_FILE="$ACCOUNT_HOME/.gemini/oauth_creds.json"
    local TMP_JSON="$TMP_DIR/${ACCOUNT_NAME}.json"
    
    if [ ! -f "$CRED_FILE" ]; then 
        echo -e "${C_OFF}[NO CRED]${C_RST}|${C_OFF}[NO CRED]${C_RST}" > "$OUT_FILE"
        return
    fi

    # Isolate Refresh: Use a private GEMINI_CLI_HOME for the ping to avoid touching real sessions in ~/.gemini/tmp
    local PING_HOME="$TMP_DIR/home_$ACCOUNT_NAME"
    mkdir -p "$PING_HOME/.gemini"
    
    # Symlink all config files from the real account to the isolated home
    for f in "$ACCOUNT_HOME/.gemini/"*; do
        [ "$(basename "$f")" == "tmp" ] && continue # Skip the shared tmp
        ln -s "$f" "$PING_HOME/.gemini/" 2>/dev/null
    done
    mkdir -p "$PING_HOME/.gemini/tmp" # Create a private tmp for this ping

    # Silent Refresh in isolated environment
    timeout 10s env HOME="$REAL_USER_HOME" GEMINI_CLI_HOME="$PING_HOME" "$GEMINI_BIN" --skip-trust -m "gemini-3-flash-preview" -p "ping" > /dev/null 2>&1

    # Sync back the refreshed token if the CLI replaced the symlink with a new file
    if [ -f "$PING_HOME/.gemini/oauth_creds.json" ] && [ ! -L "$PING_HOME/.gemini/oauth_creds.json" ]; then
        cp -f "$PING_HOME/.gemini/oauth_creds.json" "$CRED_FILE"
    fi

    local TOKEN=$(jq -r '.access_token // empty' "$CRED_FILE" 2>/dev/null)
    [ -z "$TOKEN" ] && { echo -e "${C_ERR}[TOKEN ERR]${C_RST}|${C_ERR}[TOKEN ERR]${C_RST}" > "$OUT_FILE"; return; }
    
    # Robust Project ID Extraction with Base64 Padding Fallback
    local ID_TOKEN=$(jq -r '.id_token // empty' "$CRED_FILE" 2>/dev/null)
    local PAYLOAD=$(echo "$ID_TOKEN" | cut -d. -f2)
    # Add padding to ensure valid base64
    local PADDED_PAYLOAD="${PAYLOAD}==="
    local PROJECT_ID=$(echo "$PADDED_PAYLOAD" | base64 -d 2>/dev/null | jq -r '.azp' 2>/dev/null | cut -d- -f1)
    [ -z "$PROJECT_ID" ] && PROJECT_ID="681255809395" # Fallback

    curl -s -X POST "$ENDPOINT" --max-time 10 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"project\": \"$PROJECT_ID\"}" > "$TMP_JSON" 2>/dev/null
    
    # Check for API-level errors (like 401 Unauthorized)
    if jq -e '.error' "$TMP_JSON" >/dev/null 2>&1; then
        echo -e "${C_ERR}[AUTH ERR]${C_RST}|${C_ERR}[AUTH ERR]${C_RST}" > "$OUT_FILE"
        return
    fi

    if [ ! -s "$TMP_JSON" ] || ! jq -e . "$TMP_JSON" >/dev/null 2>&1; then
        echo -e "${C_ERR}[API ERR]${C_RST}|${C_ERR}[API ERR]${C_RST}" > "$OUT_FILE"
        return
    fi

    parse_model() {
        local MODEL_ID=$1
        local BUCKET=$(jq -c ".buckets[] | select(.modelId == \"$MODEL_ID\")" "$TMP_JSON" 2>/dev/null | head -n 1)
        if [ -z "$BUCKET" ] || [ "$BUCKET" == "null" ]; then echo -e "${C_OFF}[MODEL UND]${C_RST}"; return; fi
        
        local FRAC=$(echo "$BUCKET" | jq -r '.remainingFraction // empty')
        local R_ISO=$(echo "$BUCKET" | jq -r '.resetTime // empty')
        if [ -z "$FRAC" ]; then echo -e "${C_GRN}[0.0%]${C_RST}"; return; fi
        
        local USED_PCT=$(awk "BEGIN {printf \"%.1f\", (1 - $FRAC) * 100}" 2>/dev/null || echo "0.0")
        
        local NOW=$(date -u +%s)
        local R_TS=$(date -u -d "$R_ISO" +%s 2>/dev/null || date -u --date="$R_ISO" +%s 2>/dev/null || echo "0")
        local TIME_STR=""
        if [ "$R_TS" -gt 0 ]; then
            local D=$((R_TS - NOW))
            if [ $D -gt 0 ]; then
                local H=$((D / 3600))
                local M=$(( (D % 3600) / 60 ))
                TIME_STR="${H}h${M}m"
            else TIME_STR="res"; fi
        fi

        local COLOR=$C_GRN
        local STATUS_VAL="${USED_PCT}%"
        
        if awk "BEGIN {exit !($FRAC <= 0)}" 2>/dev/null; then
            STATUS_VAL="LIMITED"
            COLOR=$C_BRED
        else
            local INT_PCT=${USED_PCT%.*}
            if [ "$INT_PCT" -ge 95 ]; then COLOR=$C_BRED
            elif [ "$INT_PCT" -ge 81 ]; then COLOR=$C_RED
            elif [ "$INT_PCT" -ge 61 ]; then COLOR=$C_BYLW
            elif [ "$INT_PCT" -ge 41 ]; then COLOR=$C_YLW
            elif [ "$INT_PCT" -ge 16 ]; then COLOR=$C_BGRN
            fi
        fi

        local RESULT="${COLOR}[${STATUS_VAL}]${C_RST}"
        
        if [ -n "$TIME_STR" ]; then
            [ "$TIME_STR" == "res" ] && RESULT="$RESULT res" || RESULT="$RESULT $TIME_STR"
        fi
        echo -e "$RESULT"
    }

    echo -e "$(parse_model "gemini-3-flash-preview")|$(parse_model "gemini-3.1-pro-preview")" > "$OUT_FILE"
}

# Run all checks in background
for ACC in $ACCOUNTS; do 
    check_account_quota "$ACC" & 
done

# Monitor and Update Display
COMPLETED=0
declare -A DONE_ACC
while [ $COMPLETED -lt $NUM_ACCOUNTS ]; do
    INDEX=0
    for ACC in $ACCOUNTS; do
        INDEX=$((INDEX + 1))
        if [ -z "${DONE_ACC[$ACC]}" ]; then
            OUT_FILE="$TMP_DIR/$ACC"
            if [ -f "$OUT_FILE" ]; then
                # Move cursor to the specific account line
                UP=$((NUM_ACCOUNTS - INDEX + 1))
                tput cuu $UP
                
                IFS='|' read -r FLASH PRO < "$OUT_FILE"
                # Clear line and print updated status
                # 18 visual chars + 9 chars ANSI = 27 chars padding
                printf "\r\033[K%-4s | %-27b | %-27b\n" "$ACC" "$FLASH" "$PRO"
                
                # Move cursor back down
                DOWN=$((UP - 1))
                [ $DOWN -gt 0 ] && tput cud $DOWN
                
                DONE_ACC[$ACC]=1
                COMPLETED=$((COMPLETED + 1))
            fi
        fi
    done
    sleep 0.2
done

echo "----------------------------------------------"
echo "Done."