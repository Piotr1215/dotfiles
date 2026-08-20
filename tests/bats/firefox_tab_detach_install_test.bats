#!/usr/bin/env bats

# Test suite for __firefox_tab_detach_install.sh
#
# The script rewrites LibreWolf profile files, so every test points it at a
# throwaway profile tree through LIBREWOLF_DIR and HOSTS_DIR, and stubs flatpak
# so the running-browser guard sees no browser.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/scripts/__firefox_tab_detach_install.sh"
    export SCRIPT

    mkdir -p "${TEST_DIR}/bin"
    printf '#!/bin/sh\nexit 0\n' > "${TEST_DIR}/bin/flatpak"
    chmod +x "${TEST_DIR}/bin/flatpak"
    export PATH="${TEST_DIR}/bin:${PATH}"

    export LIBREWOLF_DIR="${TEST_DIR}/lw"
    export HOSTS_DIR="${TEST_DIR}/hosts"
    mkdir -p "${LIBREWOLF_DIR}/p1.home/extensions" "${LIBREWOLF_DIR}/p2.work"
    printf '[Profile0]\nPath=p1.home\n\n[Profile1]\nPath=p2.work\n' > "${LIBREWOLF_DIR}/profiles.ini"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

@test "installs the xpi into every profile listed in profiles.ini" {
    run "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${LIBREWOLF_DIR}/p1.home/extensions/tab-detach@dotfiles.xpi" ]
    [ -f "${LIBREWOLF_DIR}/p2.work/extensions/tab-detach@dotfiles.xpi" ]
}

@test "xpi carries the manifest and background script at the zip root" {
    run "${SCRIPT}"
    run unzip -Z1 "${LIBREWOLF_DIR}/p1.home/extensions/tab-detach@dotfiles.xpi"
    [ "$output" = $'manifest.json\nbackground.js\ncontent.js' ]
}

@test "removes the superseded tabdetach extension" {
    touch "${LIBREWOLF_DIR}/p1.home/extensions/tabenhanced@firefox.xpi"
    run "${SCRIPT}"
    [ ! -e "${LIBREWOLF_DIR}/p1.home/extensions/tabenhanced@firefox.xpi" ]
}

@test "writes both prefs once, even when one is already there" {
    printf 'user_pref("xpinstall.signatures.required", false);\n' > "${LIBREWOLF_DIR}/p1.home/user.js"
    run "${SCRIPT}"
    run "${SCRIPT}"
    run grep -c 'user_pref' "${LIBREWOLF_DIR}/p1.home/user.js"
    [ "$output" = "2" ]
    run grep -c 'user_pref' "${LIBREWOLF_DIR}/p2.work/user.js"
    [ "$output" = "2" ]
    grep -qF 'user_pref("widget.use-xdg-desktop-portal.native-messaging", 1);' "${LIBREWOLF_DIR}/p2.work/user.js"
}

@test "links the host manifest into the mozilla hosts dir" {
    run "${SCRIPT}"
    [ -L "${HOSTS_DIR}/com.dotfiles.layouts.json" ]
    run jq -r '.allowed_extensions[0], .path' "${HOSTS_DIR}/com.dotfiles.layouts.json"
    [ "${lines[0]}" = "tab-detach@dotfiles" ]
    [ -x "${lines[1]}" ]
}

@test "refuses to run while LibreWolf is up" {
    printf '#!/bin/sh\necho io.gitlab.librewolf-community\n' > "${TEST_DIR}/bin/flatpak"
    run "${SCRIPT}"
    [ "$status" -eq 1 ]
    [ ! -e "${LIBREWOLF_DIR}/p1.home/extensions/tab-detach@dotfiles.xpi" ]
}
