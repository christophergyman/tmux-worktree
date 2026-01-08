#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/tmux"
TARGET_DIR="$HOME/.config/tmux"

# Verify source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Ensure ~/.config exists
if ! mkdir -p "$HOME/.config" 2>/dev/null; then
    echo "Error: Failed to create $HOME/.config"
    exit 1
fi

# Check if target already exists
if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
    read -p "$TARGET_DIR already exists. Overwrite? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if ! rm -rf "$TARGET_DIR"; then
            echo "Error: Failed to remove existing $TARGET_DIR"
            exit 1
        fi
    else
        echo "Aborted."
        exit 1
    fi
fi

# Create symlink
if ln -s "$SOURCE_DIR" "$TARGET_DIR"; then
    echo "Symlinked $SOURCE_DIR -> $TARGET_DIR"
else
    echo "Error: Failed to create symlink"
    exit 1
fi
