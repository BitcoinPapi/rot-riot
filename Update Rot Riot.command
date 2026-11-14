#!/bin/bash
# Double-click this file (on a Mac) to download the newest version of Rot Riot.
# It replaces this project folder with the latest one from GitHub.
# Your coins, level and upgrades are stored elsewhere and are not touched.

main() {
	local project parent name tmp
	project="$(cd "$(dirname "$0")" && pwd)"
	parent="$(dirname "$project")"
	name="$(basename "$project")"

	echo "Rot Riot updater"
	echo "Close Godot first if it is open."
	echo

	# Safety: only ever replace a folder that really is the game project.
	if [ ! -f "$project/project.godot" ] || [ -z "$name" ] || [ "$project" = "/" ] || [ "$project" = "$HOME" ]; then
		echo "This file must stay inside the Rot Riot project folder. Nothing was changed."
		return 1
	fi

	tmp="$(mktemp -d)" || return 1
	echo "1/3 downloading the newest version..."
	if ! curl -L --fail --max-time 180 -# -o "$tmp/rot-riot.zip" "https://github.com/BitcoinPapi/rot-riot/archive/refs/heads/main.zip"; then
		echo
		echo "The download failed. Check the internet connection and try again. Nothing was changed."
		rm -rf "$tmp"
		return 1
	fi

	echo "2/3 unpacking..."
	if ! unzip -q "$tmp/rot-riot.zip" -d "$tmp" || [ ! -f "$tmp/rot-riot-main/project.godot" ]; then
		echo "The download looks wrong. Nothing was changed."
		rm -rf "$tmp"
		return 1
	fi

	echo "3/3 replacing the old files..."
	rm -rf "$project"
	mv "$tmp/rot-riot-main" "$parent/$name"
	rm -rf "$tmp"
	echo
	echo "Done. Open the project in Godot again and press Play."
}

main "$@"
echo
read -r -p "Press Return to close this window. " _
