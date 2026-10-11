#!/bin/sh
# Render one frame to shots/<name>.png and quit.
# Usage: ./snap.sh name [--yaw=40 --pitch=34 --dist=48 --sun=36 --sun_yaw=125]
cd "$(dirname "$0")"
G="${GODOT:-/c/Users/oloff/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"
shift
timeout 120 "$G" --path . -- --snapshot="$PWD/shots/$name.png" "$@" </dev/null 2>&1 | grep -v -e "^$" -e "^Godot Engine" -e "^Vulkan"
true
