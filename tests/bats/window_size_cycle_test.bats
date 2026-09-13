#!/usr/bin/env bats

# __window_size_cycle.sh steps the focused window full -> left half -> square
# third on the screen the window is on. These pin the step rule, the square's
# shape and the screen choice:
# the desk is a 2560x1600 laptop screen at 0,0 and a 1920x1080 primary HDMI
# screen at 2560,0, with a 32px top panel.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/__window_size_cycle.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	export GDBUS_LOG="$BATS_TEST_TMPDIR/gdbus.log"
	mkdir -p "$STUB_BIN"
	export PATH="$STUB_BIN:$PATH"
	unset LAYOUT_MONITOR

	stub xrandr 'printf "%s\n" "Screen 0: minimum 8 x 8, current 4480 x 1600" "HDMI-0 connected primary 1920x1080+2560+0 (normal) 476mm x 267mm" "eDP-1-1 connected 2560x1600+0+0 (normal) 345mm x 215mm"'
	stub wmctrl 'echo "0  * DG: 4480x1600  VP: 0,0  WA: 0,32 4480x1568  Workspace 1"'
	stub gdbus 'shift 7; echo "$*" >> "$GDBUS_LOG"'
}

stub() {
	printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUB_BIN/$1"
	chmod +x "$STUB_BIN/$1"
}

# window X Y W H, and its _NET_WM_STATE
window() {
	stub xdotool "case \"\$1\" in getactivewindow) echo 77 ;; getwindowgeometry) printf 'WINDOW=77\nX=$1\nY=$2\nWIDTH=$3\nHEIGHT=$4\nSCREEN=0\n' ;; esac"
	stub xprop "echo '_NET_WM_STATE(ATOM) = $5'"
}

@test "a maximized window on the HDMI screen goes to its left half" {
	window 2560 32 1920 1048 "_NET_WM_STATE_MAXIMIZED_HORZ, _NET_WM_STATE_MAXIMIZED_VERT"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$GDBUS_LOG")" = "org.gnome.Shell.Extensions.TileHelper.TileXid 77 2560 32 960 1048" ]
}

@test "a half-width window on the laptop screen becomes a square third, off the left edge" {
	window 0 32 1280 1568 ""
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$GDBUS_LOG")" = "org.gnome.Shell.Extensions.TileHelper.TileXid 77 40 389 853 853" ]
}

@test "on a very wide screen the square is capped at the screen height" {
	stub xrandr 'printf "%s\n" "Screen 0: minimum 8 x 8, current 5120 x 1440" "DP-1 connected primary 5120x1440+0+0 (normal) 1190mm x 340mm"'
	stub wmctrl 'echo "0  * DG: 5120x1440  VP: 0,0  WA: 0,32 5120x1408  Workspace 1"'
	window 0 32 2560 1408 ""
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$GDBUS_LOG")" = "org.gnome.Shell.Extensions.TileHelper.TileXid 77 40 32 1408 1408" ]
}

@test "a third-width window is maximized" {
	window 2560 32 640 1048 ""
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$GDBUS_LOG")" = "org.gnome.Shell.Extensions.TileHelper.MaximizeXid 77" ]
}

@test "a hand-sized window is maximized" {
	window 300 400 1100 700 "_NET_WM_STATE_ABOVE"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$GDBUS_LOG")" = "org.gnome.Shell.Extensions.TileHelper.MaximizeXid 77" ]
}

@test "a window maximized only horizontally is not treated as full" {
	window 2560 300 1920 500 "_NET_WM_STATE_MAXIMIZED_HORZ"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$GDBUS_LOG")" = "org.gnome.Shell.Extensions.TileHelper.MaximizeXid 77" ]
}
