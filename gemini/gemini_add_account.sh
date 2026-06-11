#!/bin/bash
# Usage: bash add_account.sh <account_number>
# Example: bash add_account.sh 7

REAL_HOME="/home/woeijiunn88"
ACCOUNTS_BASE="$REAL_HOME/.gemini/accounts"

ACC_NUM=$1

if [ -z "$ACC_NUM" ]; then
    echo "No account number provided. Finding first available slot..."
    i=1
    while [ -d "$ACCOUNTS_BASE/g$i" ]; do
        i=$((i+1))
    done
    ACC_NUM=$i
    echo "Selected g$ACC_NUM"
fi

# Strip leading 'g' if present to avoid names like 'gg7'
ACC_NUM=${ACC_NUM#g}

ACC_NAME="g$ACC_NUM"
ACC_DIR="$ACCOUNTS_BASE/$ACC_NAME/.gemini"

echo "Proposed Account Name: $ACC_NAME"
echo "Proposed Directory: $ACCOUNTS_BASE/$ACC_NAME"
echo -n "Proceed with setup? (y/n): "
read -r CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo "Setting up $ACC_NAME..."
mkdir -p "$ACC_DIR"

# Helper to create symlink safely (replacing any existing directory)
safe_link() {
    local src=$1
    local dest=$2
    if [ -d "$dest" ] && [ ! -L "$dest" ]; then
        echo "Removing existing directory at $dest..."
        rm -rf "$dest"
    fi
    ln -sfn "$src" "$dest"
}

# Create Shared Brain Symlinks
safe_link "$REAL_HOME/.gemini/history" "$ACC_DIR/history"
safe_link "$REAL_HOME/.gemini/tmp" "$ACC_DIR/tmp"
safe_link "$REAL_HOME/.gemini/projects.json" "$ACC_DIR/projects.json"
safe_link "$REAL_HOME/.gemini/trustedFolders.json" "$ACC_DIR/trustedFolders.json"
safe_link "$REAL_HOME/.gemini/GEMINI.md" "$ACC_DIR/GEMINI.md"

# Add Alias to .bashrc if it doesn't exist
ALIAS_LINE="alias $ACC_NAME=\"HOME=\\\"$ACCOUNTS_BASE/$ACC_NAME\\\" /usr/bin/gemini\""

if ! grep -q "alias $ACC_NAME=" "$REAL_HOME/.bashrc"; then
    echo "Adding alias to .bashrc..."
    PREV_ACC=$((ACC_NUM - 1))
    if grep -q "alias g$PREV_ACC=" "$REAL_HOME/.bashrc"; then
        sed -i "/alias g$PREV_ACC=/a $ALIAS_LINE" "$REAL_HOME/.bashrc"
    else
        echo "$ALIAS_LINE" >> "$REAL_HOME/.bashrc"
    fi
    echo "Done. Please run 'source ~/.bashrc' or restart your terminal."
else
    echo "Alias $ACC_NAME already exists in .bashrc."
fi
