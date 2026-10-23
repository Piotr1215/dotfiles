#!/usr/bin/env bats

# Where alt-h in the bindings help (ctrl+alt+h) pastes the binding. The help
# is launched by AutoKey, outside tmux, and inherits whatever TMUX and
# TMUX_PANE AutoKey was started with. A bare `tmux display-message` answers
# from those, so it names the pane AutoKey was last restarted from, not the
# one on screen. The tmux stub models exactly that split: list-clients reports
# the pane each attached client shows, and display-message without -t reports
# $STUB_ENV_PANE, the pane the launcher's environment names.

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__config_bindings_help.sh"
	FIX="$BATS_TEST_TMPDIR/fix"
	BIN="$FIX/bin"
	mkdir -p "$BIN"
	TARGET="$FIX/__file_opener.sh"
	: >"$TARGET"
	printf 'tmux|M-x|display-popup -E "%s"|.tmux.conf:238\n' "$TARGET" >"$FIX/bindings"
	PAYLOAD="[tmux] M-x ($TARGET)"

	cat >"$BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/tmux.log"
case "\$1" in
	list-clients) [[ -n "\${STUB_CLIENTS-}" ]] && printf '%b\n' "\$STUB_CLIENTS"; exit 0 ;;
	display-message)
		shift
		target=""
		while [[ \$# -gt 0 ]]; do
			[[ \$1 == -t ]] && { target="\$2"; shift; }
			shift
		done
		if [[ -z \$target ]]; then
			printf '%s\n' "\${STUB_ENV_PANE-}"
		elif [[ " \${STUB_LIVE-} " == *" \$target "* ]]; then
			printf '%s\n' "\$target"
		fi
		exit 0 ;;
	load-buffer) cat >"$FIX/buffer"; exit 0 ;;
	*) exit 0 ;;
esac
EOF
	# alacritty runs its -e command in place; fzf presses alt-h on the first row.
	cat >"$BIN/alacritty" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 && $1 != -e ]]; do shift; done
shift
exec "$@"
EOF
	cat >"$BIN/fzf" <<'EOF'
#!/usr/bin/env bash
IFS= read -r row
cat >/dev/null
printf 'alt-h\n%s\n' "$row"
EOF
	printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/xrandr"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/wmctrl"
	printf '#!/usr/bin/env bash\necho "  dimensions:    1920x1080 pixels"\n' >"$BIN/xdpyinfo"
	printf '#!/usr/bin/env bash\ncat >"%s/clipboard"\n' "$FIX" >"$BIN/xsel"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/notify-send"
	printf '#!/usr/bin/env bash\ncat "%s/bindings"\n' "$FIX" >"$BIN/confhelp"
	chmod +x "$BIN"/*
}

press_alt_h() {
	run env PATH="$BIN:$PATH" TMPDIR="$FIX" CONFIG_BINDINGS_CACHE="$FIX/bindings" \
		TMUX="/tmp/stub-socket,1,17" TMUX_PANE="%51" \
		bash "$SCRIPT" </dev/null
}

@test "alt-h pastes into the pane on screen, not the pane AutoKey's environment names" {
	export STUB_CLIENTS='1792750000 %3\n1792757890 %7'
	export STUB_ENV_PANE='%51'
	export STUB_LIVE='%3 %7 %51'
	press_alt_h
	[ "$status" -eq 0 ]
	[ "$(cat "$FIX/buffer")" = "$PAYLOAD" ]
	grep -q "^run-shell -b .*paste-buffer -p .* -t '%7' -d" "$FIX/tmux.log"
	! grep -q "'%51'" "$FIX/tmux.log"
	[ ! -e "$FIX/clipboard" ]
}

@test "alt-h with no attached client copies the binding instead of pasting" {
	export STUB_CLIENTS=''
	export STUB_ENV_PANE='%51'
	export STUB_LIVE='%51'
	press_alt_h
	[ "$status" -eq 0 ]
	[ "$(cat "$FIX/clipboard")" = "$PAYLOAD" ]
	! grep -q '^run-shell' "$FIX/tmux.log"
}
