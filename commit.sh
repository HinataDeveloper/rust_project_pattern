#!/usr/bin/env zsh

set -e

if [[ $# -eq 0 ]]; then
    echo "error: commit message is required"
    echo "usage: $0 commit message"
    exit 1
fi

message="$*"

rm -rf src/.main.rs.bak*

git add --all

if git diff --cached --quiet; then
    echo "nothing to commit"
    git status
    exit 0
fi

git commit -m "$message"
git status
