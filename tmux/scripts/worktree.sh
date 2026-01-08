#!/bin/bash
# Git worktree helper for tmux

# Check dependencies
for cmd in git fzf tmux; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not found in PATH"
        read -n 1
        exit 1
    fi
done

ACTION="$1"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$REPO_ROOT" ]; then
    echo "Error: Not in a git repository"
    read -n 1
    exit 1
fi

WORKTREE_DIR="$REPO_ROOT/.worktrees"
if ! mkdir -p "$WORKTREE_DIR" 2>/dev/null; then
    echo "Error: Failed to create worktree directory"
    read -n 1
    exit 1
fi

case "$ACTION" in
    existing)
        # Pick from existing remote/local branches
        BRANCH=$(git branch -a --format='%(refname:short)' | fzf --prompt="Select branch: ")
        [ -z "$BRANCH" ] && exit 0
        # Strip remote prefix if this is a remote tracking branch
        # Check if branch starts with a known remote name
        REMOTE_NAME="${BRANCH%%/*}"
        if git remote | grep -qx "$REMOTE_NAME" 2>/dev/null; then
            BRANCH_NAME="${BRANCH#$REMOTE_NAME/}"
        else
            BRANCH_NAME="$BRANCH"
        fi
        ;;
    new)
        # Prompt for new branch name
        read -p "New branch name: " BRANCH_NAME
        [ -z "$BRANCH_NAME" ] && exit 0
        # Validate branch name (alphanumeric, dots, underscores, slashes, hyphens)
        if [[ ! "$BRANCH_NAME" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
            echo "Error: Invalid branch name. Use only letters, numbers, dots, underscores, slashes, hyphens."
            read -n 1
            exit 1
        fi
        ;;
    list)
        git worktree list
        echo ""
        echo "Press any key to close"
        read -n 1
        exit 0
        ;;
    delete)
        # Delete worktree only (keep branch)
        WORKTREE=$(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2- | fzf --prompt="Delete worktree (keep branch): ")
        [ -z "$WORKTREE" ] && exit 0
        if git worktree remove "$WORKTREE"; then
            echo "Removed worktree: $WORKTREE"
            echo "Branch kept"
        else
            echo "Error: Failed to remove worktree"
        fi
        read -n 1
        exit 0
        ;;
    delete-all)
        # Delete worktree AND branch
        WORKTREE=$(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2- | fzf --prompt="Delete worktree + branch: ")
        [ -z "$WORKTREE" ] && exit 0

        # Get the branch name for this worktree (using awk for safe string matching)
        BRANCH=$(git worktree list --porcelain | awk -v wt="$WORKTREE" '
            /^worktree / && substr($0, 10) == wt { found=1; next }
            found && /^branch/ { sub("branch refs/heads/", ""); print; exit }
            /^worktree/ { found=0 }
        ')

        # Remove worktree
        if ! git worktree remove "$WORKTREE"; then
            echo "Error: Failed to remove worktree"
            read -n 1
            exit 1
        fi

        # Delete branch if found (and not main/master)
        if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
            if git branch -d "$BRANCH" 2>/dev/null || git branch -D "$BRANCH" 2>/dev/null; then
                echo "Removed worktree: $WORKTREE"
                echo "Deleted branch: $BRANCH"
            else
                echo "Removed worktree: $WORKTREE"
                echo "Warning: Failed to delete branch: $BRANCH"
            fi
        else
            echo "Removed worktree: $WORKTREE"
            [ -n "$BRANCH" ] && echo "Kept branch: $BRANCH (protected)"
        fi
        read -n 1
        exit 0
        ;;
    switch)
        # Pick from existing worktrees (exclude main worktree)
        WORKTREE=$(git worktree list | tail -n +2 | fzf --prompt="Switch to worktree: " | awk '{print $1}')
        [ -z "$WORKTREE" ] && exit 0

        # Get branch name from worktree (using awk for safe string matching)
        BRANCH=$(git worktree list --porcelain | awk -v wt="$WORKTREE" '
            /^worktree / && substr($0, 10) == wt { found=1; next }
            found && /^branch/ { sub("branch refs/heads/", ""); print; exit }
            /^worktree/ { found=0 }
        ')
        SESSION_NAME=$(echo "$BRANCH" | tr './:' '-' | tr -d '\n')

        # Validate session name
        if [ -z "$SESSION_NAME" ]; then
            echo "Error: Could not determine session name (detached HEAD?)"
            read -n 1
            exit 1
        fi

        # Switch to existing session or create new one
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux switch-client -t "$SESSION_NAME"
        else
            tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE"
            tmux switch-client -t "$SESSION_NAME"
        fi
        exit 0
        ;;
    *)
        echo "Usage: $0 {existing|new|list|delete|delete-all|switch}"
        exit 1
        ;;
esac

# Sanitize branch name for directory
DIR_NAME=$(echo "$BRANCH_NAME" | tr '/' '-')
WORKTREE_PATH="$WORKTREE_DIR/$DIR_NAME"

# Create worktree
if [ "$ACTION" = "new" ]; then
    if ! git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"; then
        echo "Error: Failed to create worktree with new branch"
        read -n 1
        exit 1
    fi
else
    if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"; then
        echo "Error: Failed to create worktree"
        read -n 1
        exit 1
    fi
fi

# Create new tmux session named after branch
SESSION_NAME=$(echo "$BRANCH_NAME" | tr './:' '-' | tr -d '\n')
if [ -z "$SESSION_NAME" ]; then
    echo "Error: Could not determine session name"
    read -n 1
    exit 1
fi
if ! tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH" 2>/dev/null; then
    echo "Warning: Session '$SESSION_NAME' may already exist"
fi
tmux switch-client -t "$SESSION_NAME"
