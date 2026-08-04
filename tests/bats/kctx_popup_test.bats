#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__kctx_popup.sh"
    TEST_BIN="${BATS_TEST_TMPDIR}/bin"
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    PLUGIN_LOG="${BATS_TEST_TMPDIR}/plugin.log"
    mkdir -p "${TEST_BIN}" "${FAKE_HOME}/dev/google-cloud-sdk/bin"

    cat > "${TEST_BIN}/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    display-message) printf '%%1\n' ;;
    show-options) exit 0 ;;
    refresh-client) exit 0 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "${TEST_BIN}/tmux"

    cat > "${TEST_BIN}/kctx" <<'EOF'
#!/usr/bin/env bash
command -v gke-gcloud-auth-plugin > "${PLUGIN_LOG}"
EOF
    chmod +x "${TEST_BIN}/kctx"

    cat > "${FAKE_HOME}/dev/google-cloud-sdk/bin/gke-gcloud-auth-plugin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${FAKE_HOME}/dev/google-cloud-sdk/bin/gke-gcloud-auth-plugin"
}

@test "popup resolves the GKE auth plugin with a stripped tmux PATH" {
    run env HOME="${FAKE_HOME}" \
        PATH="${TEST_BIN}:/usr/bin:/bin" \
        KCTX_BIN="${TEST_BIN}/kctx" \
        PLUGIN_LOG="${PLUGIN_LOG}" \
        KCTX_CLAUDE_NOTIFY="${TEST_BIN}/missing-notifier" \
        /bin/bash "${SCRIPT}"

    [ "${status}" -eq 0 ]
    [ "$(<"${PLUGIN_LOG}")" = "${FAKE_HOME}/dev/google-cloud-sdk/bin/gke-gcloud-auth-plugin" ]
}
