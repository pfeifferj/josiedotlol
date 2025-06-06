#!/bin/bash
# josie.lol dotfiles installer
# Downloads and installs vimrc from josie.lol

set -euo pipefail

DOTFILES_URL="https://josie.lol"
BACKUP_DIR="$HOME/.dotfiles.backup.$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}josie.lol dotfiles installer${NC}"
echo "=============================="
echo

# Backup existing vimrc
if [ -f "$HOME/.vimrc" ]; then
    echo -e "${YELLOW}Backing up existing .vimrc to $BACKUP_DIR...${NC}"
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.vimrc" "$BACKUP_DIR/"
    echo "  Backed up .vimrc"
fi

# Download and install vimrc
echo -e "${YELLOW}Downloading vimrc...${NC}"
if curl -fsSL "$DOTFILES_URL/vimrc" -o "$HOME/.vimrc"; then
    echo -e "${GREEN}✓ Successfully installed .vimrc${NC}"
else
    echo -e "${RED}✗ Failed to download vimrc${NC}"
    exit 1
fi

echo
echo -e "${GREEN}Vimrc installation complete!${NC}"
echo "Enjoy your new vim configuration! 🚀"