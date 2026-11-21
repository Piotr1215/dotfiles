#!/usr/bin/env bats
# __set_graphics_mode.sh with sudo and system76-power stubbed: speak and base set the
# lid along with graphics and profile, on a copy of logind.conf, and never power off or reboot here.

setup() {
    script="$BATS_TEST_DIRNAME/../../scripts/__set_graphics_mode.sh"
    bin="$BATS_TEST_TMPDIR/bin"
    log="$BATS_TEST_TMPDIR/log"
    export LOGIND_CONF="$BATS_TEST_TMPDIR/logind.conf"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
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
if [[ \$# -eq 1 && \$1 == graphics ]]; then
    echo "\${GRAPHICS:-nvidia}"
elif [[ \$# -eq 1 && \$1 == profile ]]; then
    echo "Power Profile: \${PROFILE:-Balanced}"
fi
exit 0
EOF
    chmod +x "$bin/sudo" "$bin/system76-power"
    PATH="$bin:$PATH"
}

@test "check accepts consistent speak mode without sudo" {
    export GRAPHICS=hybrid PROFILE=Battery
    touch "$XDG_RUNTIME_DIR/speak-mode"
    sed -i 's/=ignore/=suspend/g' "$LOGIND_CONF"
    run "$script" check </dev/null
    [ "$status" -eq 0 ]
    [ "$output" = 'mode speak ok' ]
    ! grep -q '^sudo ' "$log"
}

@test "check accepts consistent base mode without sudo" {
    run "$script" check </dev/null
    [ "$status" -eq 0 ]
    [ "$output" = 'mode base ok' ]
    ! grep -q '^sudo ' "$log"
}

@test "check reports all mismatches in speak mode" {
    export GRAPHICS=hybrid PROFILE=Balanced
    run "$script" check </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *'mode speak mismatch:'* ]]
    [[ "$output" == *'profile=Balanced (expected Battery)'* ]]
    [[ "$output" == *'speak-flag=absent'* ]]
    [[ "$output" == *'HandleLidSwitch=ignore'* ]]
    [[ "$output" == *'HandleLidSwitchExternalPower=ignore'* ]]
    ! grep -q '^sudo ' "$log"
}

@test "check rejects balanced profile alone in speak mode" {
    export GRAPHICS=hybrid PROFILE=Balanced
    touch "$XDG_RUNTIME_DIR/speak-mode"
    sed -i 's/=ignore/=suspend/g' "$LOGIND_CONF"
    run "$script" check
    [ "$status" -eq 1 ]
    [ "$output" = 'mode speak mismatch: profile=Balanced (expected Battery)' ]
}

@test "check rejects a missing flag alone in speak mode" {
    export GRAPHICS=hybrid PROFILE=Battery
    sed -i 's/=ignore/=suspend/g' "$LOGIND_CONF"
    run "$script" check
    [ "$status" -eq 1 ]
    [ "$output" = 'mode speak mismatch: speak-flag=absent (expected present)' ]
}

@test "check rejects a flag alone in base mode" {
    touch "$XDG_RUNTIME_DIR/speak-mode"
    run "$script" check
    [ "$status" -eq 1 ]
    [ "$output" = 'mode base mismatch: speak-flag=present (expected absent)' ]
}

@test "check rejects suspend lid settings alone in base mode" {
    sed -i 's/=ignore/=suspend/g' "$LOGIND_CONF"
    run "$script" check
    [ "$status" -eq 1 ]
    [[ "$output" == *'HandleLidSwitch=suspend'* ]]
    [[ "$output" == *'HandleLidSwitchExternalPower=suspend'* ]]
}

@test "check rejects a present flag and suspend lid in base mode" {
    touch "$XDG_RUNTIME_DIR/speak-mode"
    sed -i 's/=ignore/=suspend/g' "$LOGIND_CONF"
    run "$script" check </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *'speak-flag=present'* ]]
    [[ "$output" == *'HandleLidSwitch=suspend'* ]]
    [[ "$output" == *'HandleLidSwitchExternalPower=suspend'* ]]
    ! grep -q '^sudo ' "$log"
}

@test "check rejects integrated graphics without sudo" {
    export GRAPHICS=integrated
    run "$script" check </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *'mode integrated mismatch: graphics=integrated'* ]]
    ! grep -q '^sudo ' "$log"
}

@test "check uses the last lid setting and reports unreadable inputs" {
    printf 'HandleLidSwitch=suspend\n' >> "$LOGIND_CONF"
    run "$script" check
    [ "$status" -eq 1 ]
    [[ "$output" == *'HandleLidSwitch=suspend'* ]]
    rm "$LOGIND_CONF"
    run "$script" check
    [ "$status" -eq 1 ]
    [[ "$output" == *'HandleLidSwitch=missing'* ]]
    [[ "$output" == *'HandleLidSwitchExternalPower=missing'* ]]
}

@test "login restores the battery profile for hybrid graphics" {
    export GRAPHICS=hybrid
    run "$script" login
    [ "$status" -eq 0 ]
    grep -qx 'system76-power profile battery' "$log"
    [ -f "$XDG_RUNTIME_DIR/speak-mode" ]
}

@test "login leaves the profile alone for nvidia graphics" {
    export GRAPHICS=nvidia
    touch "$XDG_RUNTIME_DIR/speak-mode"
    run "$script" login
    [ "$status" -eq 0 ]
    ! grep -q '^system76-power profile' "$log"
    [ ! -e "$XDG_RUNTIME_DIR/speak-mode" ]
}

@test "login needs no input or sudo" {
    export GRAPHICS=hybrid
    run "$script" login </dev/null
    [ "$status" -eq 0 ]
    ! grep -q '^sudo ' "$log"
}

@test "login succeeds when system76-power fails" {
    cat >"$bin/system76-power" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    run "$script" login
    [ "$status" -eq 0 ]
}

@test "login succeeds when setting the battery profile fails" {
    cat >"$bin/system76-power" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == graphics ]]; then
    echo hybrid
    exit 0
fi
exit 1
EOF
    run "$script" login
    [ "$status" -eq 0 ]
    [ -f "$XDG_RUNTIME_DIR/speak-mode" ]
}

@test "login succeeds when system76-power is missing" {
    rm "$bin/system76-power"
    ln -s "$(command -v bash)" "$bin/bash"
    run env PATH="$bin" "$script" login
    [ "$status" -eq 0 ]
}

@test "speak sets the lid to suspend" {
    run "$script" speak --yes --no-shutdown
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitch=suspend' "$LOGIND_CONF"
}

@test "speak suspends on the lid when plugged in too" {
    run "$script" speak --yes --no-shutdown
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitchExternalPower=suspend' "$LOGIND_CONF"
}

@test "base ignores the lid when plugged in" {
    sed -i 's/^HandleLidSwitchExternalPower=ignore/HandleLidSwitchExternalPower=suspend/' "$LOGIND_CONF"
    run "$script" base --yes --no-shutdown
    [ "$status" -eq 0 ]
    grep -qx 'HandleLidSwitchExternalPower=ignore' "$LOGIND_CONF"
}

@test "no shutdown when the plugged-in lid line cannot be set" {
    sed -i '/^HandleLidSwitchExternalPower=/d' "$LOGIND_CONF"
    run "$script" speak --yes
    [ "$status" -ne 0 ]
    ! grep -qE 'sudo (poweroff|reboot)' "$log"
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

@test "only the lid lines change" {
    before="$(grep -vE '^HandleLidSwitch(ExternalPower)?=' "$LOGIND_CONF")"
    run "$script" speak --yes --no-shutdown
    [ "$(grep -vE '^HandleLidSwitch(ExternalPower)?=' "$LOGIND_CONF")" == "$before" ]
    grep -qx '#HandleLidSwitchDocked=ignore' "$LOGIND_CONF"
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
