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
ln -s "$(pwd)/assets" "$dir/assets"
echo "worktree $dir (branch $branch), assets -> $(pwd)/assets"
echo "next: (cd $dir && cargo build -p iaf-godot)"
