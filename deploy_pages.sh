#!/bin/sh
# Put the web build (builds/web, from ./build.sh) on the gh-pages branch,
# which GitHub Pages serves at https://ojojboll-ui.github.io/Floating-Island/
cd "$(dirname "$0")"
[ -f builds/web/index.html ] || { echo "no web build: run ./build.sh first"; exit 1; }
T="$(mktemp -d)"
git fetch -q origin gh-pages
git worktree add -q "$T" origin/gh-pages --detach
find "$T" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp builds/web/* "$T/"
touch "$T/.nojekyll"
git -C "$T" add -A
git -C "$T" commit -q -m "Web build $(git rev-parse --short HEAD)" && git -C "$T" push -q origin HEAD:gh-pages
git worktree remove --force "$T"
