#!/bin/sh
# Compile check: print script errors only.
cd "$(dirname "$0")"
G="${GODOT:-/c/Users/oloff/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
timeout 120 "$G" --headless --path . --quit-after 5 2>&1 | grep -A1 "Parse Error\|Compile Error" | grep -v "depended\|^--" | head -20
