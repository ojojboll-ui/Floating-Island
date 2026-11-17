#!/bin/sh
# Export the Linux, Windows and web builds into builds/ and zip them: the
# desktop zips for a GitHub Release, the web zip (index.html at its root)
# for itch.io.
cd "$(dirname "$0")"
G="${GODOT:-/c/Users/oloff/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
for target in linux windows web; do
	rm -rf "builds/$target"
	mkdir -p "builds/$target"
done
"$G" --headless --path . --export-release "Linux" builds/linux/Skyholme.x86_64 >/dev/null 2>&1
"$G" --headless --path . --export-release "Windows" builds/windows/Skyholme.exe >/dev/null 2>&1
"$G" --headless --path . --export-release "Web" builds/web/index.html >/dev/null 2>&1
chmod +x builds/linux/Skyholme.x86_64
cd builds
rm -f Skyholme-linux.zip Skyholme-windows.zip Skyholme-web.zip
powershell -NoProfile -Command "Compress-Archive -Path linux\* -DestinationPath Skyholme-linux.zip; Compress-Archive -Path windows\* -DestinationPath Skyholme-windows.zip; Compress-Archive -Path web\* -DestinationPath Skyholme-web.zip" >/dev/null
ls -la FloatingIsland-*.zip
