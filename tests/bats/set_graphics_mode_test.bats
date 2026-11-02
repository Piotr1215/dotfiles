#!/usr/bin/env bats
# __set_graphics_mode.sh with sudo and system76-power stubbed: speak and base set the
# lid along with graphics and profile, on a copy of logind.conf, and never power off or reboot here.

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
case "\$1" in poweroff|reboot) exit 0 ;; esac
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
    run "$script" speak --yes --no-shutdown
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
}

@test "base puts the lid back to ignore" {
    sed -i 's/^HandleLidSwitch=ignore/HandleLidSwitch=suspend/' "$LOGIND_CONF"
    run "$script" base --yes --no-shutdown
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=ignore' "$LOGIND_CONF"
}

@test "a commented default is switched on" {
    sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=suspend/' "$LOGIND_CONF"
    run "$script" speak --yes --no-shutdown
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
    [ "$(grep -c '^#\?HandleLidSwitch=' "$LOGIND_CONF")" -eq 1 ]
}

@test "only the lid line changes" {
    before="$(grep -v '^HandleLidSwitch=' "$LOGIND_CONF")"
    run "$script" speak --yes --no-shutdown
    [ "$(grep -v '^HandleLidSwitch=' "$LOGIND_CONF")" == "$before" ]
}

@test "the lid is written before the shutdown" {
    run "$script" speak --yes
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
    [ "$(tail -1 "$log")" == "sudo poweroff" ]
    [ "$(grep -c 'sudo sed' "$log")" -eq 1 ]
}

@test "base shuts down by default" {
    run "$script" base --yes
    [ "$status" -eq 0 ]
    [ "$(tail -1 "$log")" == "sudo poweroff" ]
}

@test "--reboot reboots instead of shutting down" {
    run "$script" speak --yes --reboot
    [ "$status" -eq 0 ]
    [ "$(tail -1 "$log")" == "sudo reboot" ]
    ! grep -q 'sudo poweroff' "$log"
}

@test "--no-shutdown leaves the machine on" {
    run "$script" speak --yes --no-shutdown
    [ "$status" -eq 0 ]
    ! grep -qE 'sudo (poweroff|reboot)' "$log"
}

@test "no shutdown when the lid line cannot be set" {
    sed -i '/^HandleLidSwitch=/d' "$LOGIND_CONF"
    run "$script" speak --yes
    [ "$status" -ne 0 ]
    ! grep -qE 'sudo (poweroff|reboot)' "$log"
}

@test "declining the prompt leaves the lid alone" {
    run bash -c "echo n | '$script' speak"
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=ignore' "$LOGIND_CONF"
    [ ! -e "$log" ]
}
