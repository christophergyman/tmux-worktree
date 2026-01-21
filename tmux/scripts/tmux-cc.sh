#!/usr/bin/env bash
# Launch tmux with iTerm2 native integration (control mode)
# Gives native tabs, scrollback, and all iTerm2 features while keeping tmux persistence
# Note: Only works with iTerm2 (not Ghostty, Terminal.app, etc.)

exec tmux -CC new-session -A -s "${1:-main}"
