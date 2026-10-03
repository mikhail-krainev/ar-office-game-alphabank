#!/usr/bin/env bash
# Runs the Godot client on macOS, emulating a phone screen (counterpart of run.ps1).
#
#   ./run.sh                          Pixel 8
#   ./run.sh --device iphone_15
#   ./run.sh --device iphone_17_pro --screen-dpi 127
#   ./run.sh --office-screen          reception screen with the rotating entry and exit QR codes
#   ./run.sh --office-screen --office office_1a2b3c4d   the screen of another office (id from the admin panel)
#   ./run.sh --server http://192.168.1.5:7350
#
# The game always needs the Nakama server (server/, `docker compose up`), 127.0.0.1:7350 by default.
# The office screen gets its codes with the server's HTTP key, read from server/.env.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
project="$root/client"
devices="pixel_8 iphone_15 iphone_17_pro iphone_17_pro_max galaxy_s24 android_hd iphone_se desktop"

device="pixel_8"
screen_dpi=""
office_screen=false
office=""
game_args=()

usage() {
	echo "Usage: $0 [--device <id>] [--screen-dpi <value>] [--office-screen [--office <id>]] [--server <url>]"
	echo "Devices: $devices"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--device) device="${2:?}"; shift 2 ;;
		--screen-dpi) screen_dpi="${2:?}"; shift 2 ;;
		--office-screen) office_screen=true; shift ;;
		--office) office="${2:?}"; shift 2 ;;
		--server) game_args+=("--server=${2:?}"); shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 1 ;;
	esac
done

if [[ " $devices " != *" $device "* ]]; then
	echo "Unknown device '$device'." >&2
	usage >&2
	exit 1
fi

# Godot: tools/godot/Godot.app, then PATH, then /Applications.
godot=""
for candidate in "$root/tools/godot/Godot.app/Contents/MacOS/Godot" "$(command -v godot || true)" \
	"/Applications/Godot.app/Contents/MacOS/Godot"; do
	if [[ -n "$candidate" && -x "$candidate" ]]; then
		godot="$candidate"
		break
	fi
done
if [[ -z "$godot" ]]; then
	echo "Godot not found. Install Godot 4.7: brew install --cask godot" >&2
	exit 1
fi

if [[ ! -d "$project/.godot" ]]; then
	echo "First run: importing assets..."
	"$godot" --headless --path "$project" --import
fi

args=(--path "$project")
if $office_screen; then
	args+=(res://scenes/kiosk/office_screen.tscn --resolution 720x960)
	key="$(grep -E '^NAKAMA_HTTP_KEY=' "$root/server/.env" 2>/dev/null | cut -d= -f2- || true)"
	if [[ -n "$key" ]]; then
		game_args+=("--kiosk-key=$key")
	else
		echo "NAKAMA_HTTP_KEY not found in server/.env: the office screen cannot get its codes." >&2
	fi
	if [[ -n "$office" ]]; then
		game_args+=("--kiosk-office=$office")
	fi
	if [[ ${#game_args[@]} -gt 0 ]]; then
		args+=(-- "${game_args[@]}")
	fi
else
	if [[ "$device" != "desktop" ]]; then
		game_args+=("--device=$device")
		if [[ -n "$screen_dpi" ]]; then
			game_args+=("--screen-dpi=$screen_dpi")
		fi
	fi
	if [[ ${#game_args[@]} -gt 0 ]]; then
		args+=(-- "${game_args[@]}")
	fi
fi

exec "$godot" "${args[@]}"
