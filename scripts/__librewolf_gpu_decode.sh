#!/usr/bin/env bash
set -eo pipefail

# Keeps the LibreWolf flatpak decoding video on the NVIDIA GPU.
# The flatpak NVIDIA extension ships no VA-API driver, so on 2026-10-19 YouTube
# decoded on the CPU. Four pieces fix it:
#   1. nvidia-vaapi-driver built against LibreWolf's runtime, in $app_dir/vaapi
#   2. a stamp (vaapi/built-for) naming that runtime and driver version
#   3. sandbox env in the flatpak override
#   4. VA-API prefs in the profile's user.js
# Building the driver (nvidia-vaapi-driver v0.0.18 against the flatpak runtime)
# is manual. Run `stamp` afterwards to record it.
#
# Usage: __librewolf_gpu_decode.sh {check|prefs|stamp}

readonly app_id="io.gitlab.librewolf-community"
readonly driver_version="0.0.18"

app_dir="${LIBREWOLF_APP_DIR:-$HOME/.var/app/${app_id}}"
driver="${app_dir}/vaapi/nvidia_drv_video.so"
stamp_file="${app_dir}/vaapi/built-for"

readonly prefs_wanted=(
	'user_pref("media.ffmpeg.vaapi.enabled", true);'
	'user_pref("media.hardware-video-decoding.force-enabled", true);'
	'user_pref("gfx.x11-egl.force-enabled", true);'
)
# Revert from 2026-09-08 that turned VA-API off; it must not survive.
readonly pref_revert='user_pref("media.ffmpeg.vaapi.enabled", false);'

# Print the profile dir: the env override, else the Default= of [Install*].
profile_dir() {
	if [[ -n "${LIBREWOLF_PROFILE_DIR:-}" ]]; then
		echo "$LIBREWOLF_PROFILE_DIR"
		return
	fi
	local ini="${app_dir}/.librewolf/profiles.ini" rel
	rel="$(awk '/^\[/ { in_install = ($0 ~ /^\[Install/) } in_install && /^Default=/ { sub(/^Default=/, ""); print; exit }' "$ini")"
	if [[ -z "$rel" ]]; then
		echo "no Default= profile in $ini" >&2
		return 1
	fi
	echo "${app_dir}/.librewolf/${rel}"
}

# Print "<runtime> v<driver version>", the content of the build stamp.
expected_stamp() {
	local runtime
	runtime="$(flatpak info --show-runtime "$app_id")"
	echo "${runtime} v${driver_version}"
}

# Report every missing piece, one line each. Exit 1 if any.
check() {
	local failed=0 want have override js line
	local -a env_wanted=(
		"LIBVA_DRIVER_NAME=nvidia"
		"LIBVA_DRIVERS_PATH=${app_dir}/vaapi"
		"MOZ_DISABLE_RDD_SANDBOX=1"
	)

	if [[ ! -f "$driver" ]]; then
		echo "driver: ${driver} not found"
		failed=1
	fi

	want="$(expected_stamp)"
	have="none"
	[[ -f "$stamp_file" ]] && have="$(<"$stamp_file")"
	if [[ "$have" != "$want" ]]; then
		echo "driver build: have '${have}', need '${want}'"
		failed=1
	fi

	# Captured, not piped: an early grep exit would SIGPIPE the writer.
	override="$(flatpak override --user --show "$app_id")"
	for line in "${env_wanted[@]}"; do
		if ! grep -qxF "$line" <<<"$override"; then
			echo "env: ${line}"
			failed=1
		fi
	done

	js="$(profile_dir)/user.js"
	for line in "${prefs_wanted[@]}"; do
		if [[ ! -f "$js" ]] || ! grep -qxF "$line" "$js"; then
			echo "pref: ${line}"
			failed=1
		fi
	done

	((failed)) && return 1
	echo "ok: GPU video decode is wired"
}

# Idempotently write the wanted prefs to user.js and drop the revert line.
prefs() {
	local js line
	js="$(profile_dir)/user.js"
	touch "$js"
	# grep -v exits 1 when nothing is left; that is fine for an empty file.
	grep -vxF "$pref_revert" "$js" >"${js}.tmp" || true
	for line in "${prefs_wanted[@]}"; do
		grep -qxF "$line" "${js}.tmp" || echo "$line" >>"${js}.tmp"
	done
	mv "${js}.tmp" "$js"
}

# Record the runtime and driver version the driver was built for.
stamp() {
	expected_stamp >"$stamp_file"
}

case "${1:-}" in
check) check ;;
prefs) prefs ;;
stamp) stamp ;;
*)
	echo "usage: ${0##*/} {check|prefs|stamp}" >&2
	exit 1
	;;
esac
