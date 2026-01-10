#!/bin/bash
# Git worktree helper for tmux

# Get branch name from worktree path using porcelain output
get_branch_for_worktree() {
    local wt="$1"
    git worktree list --porcelain | awk -v wt="$wt" '
        /^worktree / && substr($0, 10) == wt { found=1; next }
        found && /^branch/ { sub("branch refs/heads/", ""); print; exit }
        /^worktree/ { found=0 }
    '
}

# Check dependencies
for cmd in git fzf tmux; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not found in PATH"
        read -n 1
        exit 1
    fi
done

ACTION="$1"
# Get main repo root (works from both main repo and worktrees)
GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
REPO_ROOT=$(dirname "${GIT_DIR%/worktrees/*}")

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
        # Pick from remote branches (excludes HEAD pointer)
        BRANCH=$(git branch -r --format='%(refname:short)' | grep -v '/HEAD$' | fzf --prompt="Select branch: ")
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

        # Get branch name for session cleanup
        BRANCH=$(get_branch_for_worktree "$WORKTREE")
        if [ -n "$BRANCH" ]; then
            SESSION_NAME=$(echo "$BRANCH" | tr './:' '-' | tr -d '\n')
            tmux kill-session -t "$SESSION_NAME" 2>/dev/null
        fi

        if git worktree remove "$WORKTREE"; then
            git worktree prune
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

        BRANCH=$(get_branch_for_worktree "$WORKTREE")

        # Kill tmux session for this worktree
        if [ -n "$BRANCH" ]; then
            SESSION_NAME=$(echo "$BRANCH" | tr './:' '-' | tr -d '\n')
            tmux kill-session -t "$SESSION_NAME" 2>/dev/null
        fi

        # Remove worktree
        if ! git worktree remove "$WORKTREE"; then
            echo "Error: Failed to remove worktree"
            read -n 1
            exit 1
        fi

        # Prune stale worktree metadata
        git worktree prune

        # Delete branch if found (and not main/master)
        if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
            # Try safe delete first
            if git branch -d "$BRANCH" 2>/dev/null; then
                echo "Removed worktree: $WORKTREE"
                echo "Deleted branch: $BRANCH"
            else
                # Branch has unmerged changes - ask user
                echo "Warning: Branch '$BRANCH' has unmerged changes."
                read -p "Force delete anyway? [y/N] " response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    if git branch -D "$BRANCH" 2>/dev/null; then
                        echo "Removed worktree: $WORKTREE"
                        echo "Force deleted branch: $BRANCH"
                    else
                        echo "Removed worktree: $WORKTREE"
                        echo "Error: Failed to delete branch: $BRANCH"
                    fi
                else
                    echo "Removed worktree: $WORKTREE"
                    echo "Kept branch: $BRANCH"
                fi
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

        BRANCH=$(get_branch_for_worktree "$WORKTREE")
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

# Check if worktree already exists for this branch
EXISTING_WT=$(git worktree list --porcelain | awk -v branch="refs/heads/$BRANCH_NAME" '
    /^worktree / { wt=substr($0, 10) }
    /^branch / && substr($0, 8) == branch { print wt; exit }
')
if [ -n "$EXISTING_WT" ]; then
    echo "Error: Worktree already exists for branch '$BRANCH_NAME'"
    echo "Location: $EXISTING_WT"
    echo ""
    echo "Use 'g s' to switch to it, or delete it first."
    read -n 1
    exit 1
fi

# Get the default branch for new worktrees
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
    # Fallback: check if main exists, otherwise master
    if git show-ref --verify --quiet refs/heads/main; then
        DEFAULT_BRANCH="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        DEFAULT_BRANCH="master"
    else
        echo "Error: Could not determine default branch"
        read -n 1
        exit 1
    fi
fi

# Create worktree
if [ "$ACTION" = "new" ]; then
    if ! git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$DEFAULT_BRANCH"; then
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

# Check if session exists, reuse it if so
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Session '$SESSION_NAME' already exists, switching to it"
    sleep 1
fi

# Create session if needed, then switch
tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH" 2>/dev/null
if ! tmux switch-client -t "$SESSION_NAME" 2>/dev/null; then
    echo "Error: Failed to switch to session '$SESSION_NAME'"
    read -n 1
    exit 1
fi
