#!/usr/bin/env bash
# Creates a git worktree for a parallel job, sharing the (gitignored) game data by a symlink:
#   tools/worktree.sh <name> [branch]   ->  ../iaf-reborn-<name> on branch <branch> (default: wt/<name>)
# The worktree keeps its own target/ (the Godot extension is built per worktree) and its own game/.godot cache.
set -euo pipefail
cd "$(dirname "$0")/.."
name=${1:?usage: tools/worktree.sh <name> [branch]}
branch=${2:-wt/$name}
dir="../iaf-reborn-$name"
git worktree add -b "$branch" "$dir"
# The assets symlink must never be committed: a merge of a commit holding it in a checkout with the real assets/
# makes git delete the (ignored) data dir and write the symlink. .gitignore has /assets; info/exclude covers branches
# from before that.
ex="$(git rev-parse --git-common-dir)/info/exclude"
grep -qx /assets "$ex" 2>/dev/null || echo /assets >>"$ex"
ln -s "$(pwd)/assets" "$dir/assets"
echo "worktree $dir (branch $branch), assets -> $(pwd)/assets"
echo "next: (cd $dir && cargo build -p iaf-godot)"
