#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/tmux"
TARGET_DIR="$HOME/.config/tmux"

# Ensure ~/.config exists
mkdir -p "$HOME/.config"

# Check if target already exists
if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
    read -p "$TARGET_DIR already exists. Overwrite? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$TARGET_DIR"
    else
        echo "Aborted."
        exit 1
    fi
fi

# Create symlink
ln -s "$SOURCE_DIR" "$TARGET_DIR"
echo "Symlinked $SOURCE_DIR -> $TARGET_DIR"
