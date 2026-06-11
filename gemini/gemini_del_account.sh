#!/bin/bash
# Usage: bash del_account.sh <account_number>
# Example: bash del_account.sh 7

REAL_HOME="/home/woeijiunn88"
ACCOUNTS_BASE="$REAL_HOME/.gemini/accounts"

ACC_NUM=$1

if [ -z "$ACC_NUM" ]; then
    echo "Existing accounts:"
    ls -1 "$ACCOUNTS_BASE" | sort -V | xargs echo
    echo -n "Enter account number to delete (e.g. 5 or g5): "
    read -r ACC_NUM
fi

if [ -z "$ACC_NUM" ]; then
    echo "No account number provided. Exiting."
    exit 1
fi

# Strip leading 'g' if present
ACC_NUM=${ACC_NUM#g}

if [[ ! $ACC_NUM =~ ^[0-9]+$ ]]; then
    echo "Usage: $0 <account_number> (must be a number or g<number>)"
    exit 1
fi

ACC_NAME="g$ACC_NUM"
ACC_DIR="$ACCOUNTS_BASE/$ACC_NAME"

if [ ! -d "$ACC_DIR" ]; then
    echo "Account $ACC_NAME not found."
    exit 1
fi

# Safety check: ensure we are only deleting from the accounts vault
if [[ "$ACC_DIR" != *"$ACCOUNTS_BASE/"* ]]; then
    echo "Critical Error: Refusing to delete path outside of accounts vault."
    exit 1
fi

echo "Removing $ACC_NAME..."
rm -rf "$ACC_DIR"

echo "Removing alias from .bashrc..."
sed -i "/alias $ACC_NAME=/d" "$REAL_HOME/.bashrc"

echo "Done. Please run 'source ~/.bashrc' or restart your terminal."
