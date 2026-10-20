#!/usr/bin/env bats

# __librewolf_gpu_decode.sh keeps the LibreWolf flatpak decoding video on the
# NVIDIA GPU. On 2026-10-19 every YouTube video decoded on the CPU (VP9 4K60
# held the decoder at 227% and dropped 1 frame in 100) because the flatpak's
# NVIDIA extension ships no VA-API driver. The fix is four pieces: a driver
# built against LibreWolf's runtime, a stamp naming that runtime, sandbox env in
# the flatpak override, and VA-API prefs in user.js. `check` must name each
# missing piece, and a LibreWolf update that moves the runtime must read as a
# stale build. flatpak is a stub, so no test touches the real app.

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__librewolf_gpu_decode.sh"
	WORK="$(mktemp -d)"
	export LIBREWOLF_APP_DIR="${WORK}/app"
	export LIBREWOLF_PROFILE_DIR="${WORK}/profile"
	export FAKE_RUNTIME="org.freedesktop.Platform/x86_64/25.08"
	export FAKE_OVERRIDE="${WORK}/override"
	mkdir -p "${WORK}/bin" "${LIBREWOLF_APP_DIR}/vaapi" "$LIBREWOLF_PROFILE_DIR"

	cat >"${WORK}/bin/flatpak" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
"info --show-runtime "*) echo "$FAKE_RUNTIME" ;;
"override --user --show") cat "$FAKE_OVERRIDE" ;;
esac
EOF
	chmod +x "${WORK}/bin/flatpak"
	export PATH="${WORK}/bin:${PATH}"

	JS="${LIBREWOLF_PROFILE_DIR}/user.js"
	VAAPI_ON='user_pref("media.ffmpeg.vaapi.enabled", true);'
	FORCE='user_pref("media.hardware-video-decoding.force-enabled", true);'
	EGL='user_pref("gfx.x11-egl.force-enabled", true);'
}

teardown() {
	rm -rf "$WORK"
}

# Everything in place, as after a successful install.
wire_all() {
	touch "${LIBREWOLF_APP_DIR}/vaapi/nvidia_drv_video.so"
	echo "org.freedesktop.Platform/x86_64/25.08 v0.0.18" >"${LIBREWOLF_APP_DIR}/vaapi/built-for"
	printf '%s\n' '[Context]' 'devices=all;' '' '[Environment]' \
		'LIBVA_DRIVER_NAME=nvidia' "LIBVA_DRIVERS_PATH=${LIBREWOLF_APP_DIR}/vaapi" \
		'LIBVA_MESSAGING_LEVEL=1' 'MOZ_DISABLE_RDD_SANDBOX=1' >"$FAKE_OVERRIDE"
	printf '%s\n' "$VAAPI_ON" "$FORCE" "$EGL" >"$JS"
}

@test "check passes when driver, build stamp, sandbox env and prefs are in place" {
	wire_all
	run "$SCRIPT" check
	[ "$status" -eq 0 ]
	[ "$output" = "ok: GPU video decode is wired" ]
}

@test "check names the decoder sandbox variable when the override lost it" {
	wire_all
	sed -i '/MOZ_DISABLE_RDD_SANDBOX/d' "$FAKE_OVERRIDE"
	run "$SCRIPT" check
	[ "$status" -eq 1 ]
	[ "$output" = "env: MOZ_DISABLE_RDD_SANDBOX=1" ]
}

@test "check reads a LibreWolf runtime move as a stale driver build" {
	wire_all
	FAKE_RUNTIME="org.freedesktop.Platform/x86_64/26.08"
	run "$SCRIPT" check
	[ "$status" -eq 1 ]
	[ "$output" = "driver build: have 'org.freedesktop.Platform/x86_64/25.08 v0.0.18', need 'org.freedesktop.Platform/x86_64/26.08 v0.0.18'" ]
}

@test "check reports a deleted driver" {
	wire_all
	rm "${LIBREWOLF_APP_DIR}/vaapi/nvidia_drv_video.so"
	run "$SCRIPT" check
	[ "$status" -eq 1 ]
	[ "$output" = "driver: ${LIBREWOLF_APP_DIR}/vaapi/nvidia_drv_video.so not found" ]
}

@test "check names the pref user.js lost" {
	wire_all
	printf '%s\n' "$VAAPI_ON" "$EGL" >"$JS"
	run "$SCRIPT" check
	[ "$status" -eq 1 ]
	[ "$output" = "pref: $FORCE" ]
}

@test "prefs drops the 2026-09-08 vaapi revert and keeps unrelated prefs" {
	printf '%s\n' 'user_pref("xpinstall.signatures.required", false);' \
		'user_pref("media.ffmpeg.vaapi.enabled", false);' >"$JS"
	run "$SCRIPT" prefs
	[ "$status" -eq 0 ]
	run grep -c 'vaapi.enabled", false' "$JS"
	[ "$output" = "0" ]
	grep -qxF 'user_pref("xpinstall.signatures.required", false);' "$JS"
	grep -qxF "$VAAPI_ON" "$JS"
	grep -qxF "$FORCE" "$JS"
	grep -qxF "$EGL" "$JS"
}

@test "prefs run twice writes each pref once" {
	"$SCRIPT" prefs
	first="$(cat "$JS")"
	"$SCRIPT" prefs
	[ "$(cat "$JS")" = "$first" ]
	[ "$(grep -cxF "$FORCE" "$JS")" -eq 1 ]
}
