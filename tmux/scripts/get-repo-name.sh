#!/bin/bash
# Get git repository name from a given path
# Usage: get-repo-name.sh [path]
# Returns: repository name or exits with error

path="${1:-.}"

# Get the git common directory (works for both main repo and worktrees)
git_dir=$(git -C "$path" rev-parse --git-common-dir 2>/dev/null) || exit 1

# Convert to absolute path (fixes main repo returning relative ".git")
abs_path=$(realpath "$git_dir" 2>/dev/null) || exit 1

# Strip .git suffix and worktree paths to get repo root
repo_path=$(echo "$abs_path" | sed 's|/\.git$||; s|/\.git/worktrees/.*||')

# Return just the repo name
basename "$repo_path"
