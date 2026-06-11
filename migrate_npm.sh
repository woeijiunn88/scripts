#!/bin/bash

# Exit on error
set -e

echo "Starting NPM migration to non-sudo setup..."

# 1. Create the new global directory
NEW_NPM_DIR="/home/woeijiunn88/.npm-global"
echo "Creating $NEW_NPM_DIR..."
mkdir -p "$NEW_NPM_DIR"

# 2. Configure NPM prefix
echo "Configuring npm prefix..."
# We use --userconfig to ensure it targets the correct .npmrc regardless of $HOME redirection
npm config set prefix "$NEW_NPM_DIR" --userconfig "/home/woeijiunn88/.npmrc"

# 3. Update .bashrc
BASHRC="/home/woeijiunn88/.bashrc"
PATH_LINE='export PATH="/home/woeijiunn88/.npm-global/bin:$PATH"'

echo "Updating $BASHRC..."
if ! grep -Fxq "$PATH_LINE" "$BASHRC"; then
    echo "Adding path to $BASHRC..."
    echo "" >> "$BASHRC"
    echo "# NPM non-sudo global packages" >> "$BASHRC"
    echo "$PATH_LINE" >> "$BASHRC"
else
    echo "Path already exists in $BASHRC, skipping path update..."
fi

# Update gemini aliases to use the PATH instead of hardcoded /usr/bin/gemini
if grep -q "/usr/bin/gemini" "$BASHRC"; then
    echo "Updating gemini aliases in $BASHRC to be path-independent..."
    sed -i 's/\/usr\/bin\/gemini/gemini/g' "$BASHRC"
else
    echo "No hardcoded gemini paths found in $BASHRC."
fi

# 4. Reinstall all global packages (including gemini-cli)
# We include @google/gemini-cli here. It is safe to install even while 
# this session is running because it installs to a new parallel directory
# (~/.npm-global) and does not overwrite the currently running binary in /usr.
PACKAGES="coffeescript gulp nativefier yarn node-gyp nopt semver @google/gemini-cli"

echo "Installing global packages to $NEW_NPM_DIR..."
echo "Packages: $PACKAGES"
echo "This may take a minute..."
npm install -g $PACKAGES

echo ""
echo "Migration complete!"
echo "--------------------------------------------------"
echo "1. To apply changes to this session, run:"
echo "   source ~/.bashrc"
echo ""
echo "2. Your 'g1-g7' aliases have been updated to be path-independent."
echo "   They will now prefer your local Gemini installation."
echo ""
echo "3. To cleanup old system packages (requires sudo), run:"
echo "   sudo npm uninstall -g $PACKAGES"
echo "--------------------------------------------------"
