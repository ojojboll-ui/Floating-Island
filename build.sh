#!/bin/sh
# Export the Linux and Windows builds into builds/, each with the raw assets
# beside the program (the assets folder is .gdignore'd, so it is not packed),
# and zip them for a GitHub Release.
cd "$(dirname "$0")"
G="${GODOT:-/c/Users/oloff/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
for target in linux windows; do
	rm -rf "builds/$target"
	mkdir -p "builds/$target"
done
"$G" --headless --path . --export-release "Linux" builds/linux/FloatingIsland.x86_64 >/dev/null 2>&1
"$G" --headless --path . --export-release "Windows" builds/windows/FloatingIsland.exe >/dev/null 2>&1
for target in linux windows; do
	mkdir -p "builds/$target/assets"
	cp -r assets/quaternius "builds/$target/assets/"
	rm -f "builds/$target/assets/quaternius/.gdignore"
done
chmod +x builds/linux/FloatingIsland.x86_64
cd builds
rm -f FloatingIsland-linux.zip FloatingIsland-windows.zip
powershell -NoProfile -Command "Compress-Archive -Path linux\* -DestinationPath FloatingIsland-linux.zip; Compress-Archive -Path windows\* -DestinationPath FloatingIsland-windows.zip" >/dev/null
ls -la FloatingIsland-*.zip
