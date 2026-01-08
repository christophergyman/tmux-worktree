#!/bin/bash
# Git worktree helper for tmux

ACTION="$1"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$REPO_ROOT" ]; then
    echo "Error: Not in a git repository"
    read -n 1
    exit 1
fi

WORKTREE_DIR="$REPO_ROOT/.worktrees"
mkdir -p "$WORKTREE_DIR"

case "$ACTION" in
    existing)
        # Pick from existing remote/local branches
        BRANCH=$(git branch -a --format='%(refname:short)' | ~/.fzf/bin/fzf --prompt="Select branch: ")
        [ -z "$BRANCH" ] && exit 0
        # Strip origin/ prefix if present
        BRANCH_NAME="${BRANCH#origin/}"
        ;;
    new)
        # Prompt for new branch name
        read -p "New branch name: " BRANCH_NAME
        [ -z "$BRANCH_NAME" ] && exit 0
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
        WORKTREE=$(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2 | ~/.fzf/bin/fzf --prompt="Delete worktree (keep branch): ")
        [ -z "$WORKTREE" ] && exit 0
        git worktree remove "$WORKTREE"
        echo "Removed worktree: $WORKTREE"
        echo "Branch kept"
        read -n 1
        exit 0
        ;;
    delete-all)
        # Delete worktree AND branch
        WORKTREE=$(git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2 | ~/.fzf/bin/fzf --prompt="Delete worktree + branch: ")
        [ -z "$WORKTREE" ] && exit 0

        # Get the branch name for this worktree
        BRANCH=$(git worktree list --porcelain | grep -A2 "^worktree $WORKTREE$" | grep "^branch" | sed 's/branch refs\/heads\///')

        # Remove worktree
        git worktree remove "$WORKTREE"

        # Delete branch if found (and not main/master)
        if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
            git branch -d "$BRANCH" 2>/dev/null || git branch -D "$BRANCH"
            echo "Removed worktree: $WORKTREE"
            echo "Deleted branch: $BRANCH"
        else
            echo "Removed worktree: $WORKTREE"
            [ -n "$BRANCH" ] && echo "Kept branch: $BRANCH (protected)"
        fi
        read -n 1
        exit 0
        ;;
    switch)
        # Pick from existing worktrees (exclude main worktree)
        WORKTREE=$(git worktree list | tail -n +2 | ~/.fzf/bin/fzf --prompt="Switch to worktree: " | awk '{print $1}')
        [ -z "$WORKTREE" ] && exit 0

        # Get branch name from worktree
        BRANCH=$(git worktree list --porcelain | grep -A2 "^worktree $WORKTREE$" | grep "^branch" | sed 's/branch refs\/heads\///')
        SESSION_NAME=$(echo "$BRANCH" | tr './' '-')

        # Switch to existing session or create new one
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux switch-client -t "$SESSION_NAME"
        else
            tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE"
            tmux switch-client -t "$SESSION_NAME"
        fi
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
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"
else
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
fi

if [ $? -eq 0 ]; then
    # Create new tmux session named after branch
    SESSION_NAME=$(echo "$BRANCH_NAME" | tr './' '-')
    tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH"
    tmux switch-client -t "$SESSION_NAME"
fi
