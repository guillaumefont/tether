#!/usr/bin/env bash
# Record vertical gameplay clips with Godot's movie mode (offline, frame by frame,
# so it works on machines without a GPU). Each clip is a real race on autopilot.
#
#   tools/promo/record.sh <out_dir> <track>,<variant>,<seconds>[,<mode>] ...
#
# GODOT (default: godot) is the Godot 4.7 binary; W/H/FPS set the frame size (default 1080x1920 @ 30).
# Needs a display: under Linux without one, it runs itself through xvfb-run.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
W=${W:-1080}; H=${H:-1920}; FPS=${FPS:-30}
out=$1; shift
mkdir -p "$out"
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
	run=(xvfb-run -a -s "-screen 0 $((W + 64))x$((H + 64))x24")
else
	run=()
fi
# movie mode records at the project's viewport size, so override it for the run only
trap 'rm -f override.cfg' EXIT
printf '[display]\n\nwindow/size/viewport_width=%d\nwindow/size/viewport_height=%d\n' "$W" "$H" > override.cfg
for shot in "$@"; do
	name="clip_${shot//,/_}"
	echo "== $shot -> $out/$name.avi"
	"${run[@]}" "$GODOT" --path . --rendering-method gl_compatibility \
		--write-movie "$out/$name.avi" --fixed-fps "$FPS" -- --promo="$shot" 2>&1 | grep -E "frames at|ERROR" || true
done
