# Reassert a sticky pane connection after direnv, and restore direnv when the
# override is released. This file is sourced by .zshrc after `direnv hook zsh`.

typeset -g __kctx_pane_override_active=${__kctx_pane_override_active:-0}

__kctx_apply_pane_override() {
    [[ -n "$TMUX" ]] || return 0

    local kctx_bin="${KCTX_BIN:-kctx}"
    local direnv_bin="${KCTX_DIRENV_BIN:-direnv}"
    local pane_kubeconfig
    if pane_kubeconfig="$("$kctx_bin" runtime override 2>/dev/null)"; then
        export KUBECONFIG="$pane_kubeconfig"
        __kctx_pane_override_active=1
        return 0
    fi

    [[ "$__kctx_pane_override_active" == 1 ]] || return 0

    # The popup cannot mutate its target shell. On the first command after a
    # release, discard the pane pair and make direnv recompute this directory.
    # With no exported KUBECONFIG in .envrc, the variable intentionally stays
    # unset and kubectl uses its normal ~/.kube/config fallback.
    unset KUBECONFIG
    "$direnv_bin" reload >/dev/null 2>&1 || true
    local direnv_export
    if direnv_export="$("$direnv_bin" export zsh 2>/dev/null)"; then
        eval "$direnv_export"
    fi
    __kctx_pane_override_active=0
}
