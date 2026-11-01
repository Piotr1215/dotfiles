#!/usr/bin/env bats
# __set_graphics_mode.sh with sudo and system76-power stubbed: speak and base set the
# lid along with graphics and profile, on a copy of logind.conf, and never reboot here.

setup() {
    script="$BATS_TEST_DIRNAME/../../scripts/__set_graphics_mode.sh"
    bin="$BATS_TEST_TMPDIR/bin"
    log="$BATS_TEST_TMPDIR/log"
    export LOGIND_CONF="$BATS_TEST_TMPDIR/logind.conf"
    mkdir -p "$bin"
    cat >"$LOGIND_CONF" <<'EOF'
[Login]
#KillUserProcesses=no
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
#HandleLidSwitchDocked=ignore
EOF
    cat >"$bin/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$1" >>"$log"
[[ "\$1" == reboot ]] && exit 0
exec "\$@"
EOF
    cat >"$bin/system76-power" <<EOF
#!/usr/bin/env bash
echo "system76-power \$*" >>"$log"
EOF
    chmod +x "$bin/sudo" "$bin/system76-power"
    PATH="$bin:$PATH"
}

@test "speak sets the lid to suspend" {
    run "$script" speak --yes --no-reboot
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
}

@test "base puts the lid back to ignore" {
    sed -i 's/^HandleLidSwitch=ignore/HandleLidSwitch=suspend/' "$LOGIND_CONF"
    run "$script" base --yes --no-reboot
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=ignore' "$LOGIND_CONF"
}

@test "a commented default is switched on" {
    sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=suspend/' "$LOGIND_CONF"
    run "$script" speak --yes --no-reboot
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
    [ "$(grep -c '^#\?HandleLidSwitch=' "$LOGIND_CONF")" -eq 1 ]
}

@test "only the lid line changes" {
    before="$(grep -v '^HandleLidSwitch=' "$LOGIND_CONF")"
    run "$script" speak --yes --no-reboot
    [ "$(grep -v '^HandleLidSwitch=' "$LOGIND_CONF")" == "$before" ]
}

@test "the lid is written before the reboot" {
    run "$script" speak --yes
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
    [ "$(tail -1 "$log")" == "sudo reboot" ]
    [ "$(grep -c 'sudo sed' "$log")" -eq 1 ]
}

@test "no reboot when the lid line cannot be set" {
    sed -i '/^HandleLidSwitch=/d' "$LOGIND_CONF"
    run "$script" speak --yes
    [ "$status" -ne 0 ]
    ! grep -q 'sudo reboot' "$log"
}

@test "declining the prompt leaves the lid alone" {
    run bash -c "echo n | '$script' speak"
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=ignore' "$LOGIND_CONF"
    [ ! -e "$log" ]
}
