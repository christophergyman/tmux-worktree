#!/bin/bash
cat << 'EOF'

    Vim-Style Tmux Cheatsheet
    ─────────────────────────

  PANES
    h/j/k/l     Navigate
    H/J/K/L     Resize
    v           Vertical split
    s           Horizontal split
    x           Kill pane

  WINDOWS
    C-h/C-l     Prev/Next
    Tab         Last window
    c           New window
    X           Kill window

  COPY MODE
    Escape      Enter copy mode
    v/V         Select/Line select
    y           Yank
    p           Paste

  SESSIONS
    S           Session chooser
    N           New session

  GIT WORKTREES
    g w         Worktree from branch
    g W         Worktree + new branch
    g s         Switch to worktree
    g l         List worktrees
    g d         Del worktree only
    g D         Del worktree + branch

  Press any key to close
EOF
read -n 1
