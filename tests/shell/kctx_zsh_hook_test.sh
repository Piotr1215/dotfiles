#!/usr/bin/env zsh
emulate -L zsh

pass=0
fail=0
ok()  { print -r -- "  ok   $1"; (( pass++ )); return 0 }
bad() { print -r -- "  FAIL $1"; (( fail++ )); return 0 }
is()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (got [$2] want [$3])" }

typeset -g MOCK_OVERRIDE_ACTIVE=0
typeset -g MOCK_DIRENV_EXPORT=
typeset -g MOCK_DIRENV_RELOAD_STATUS=0

__test_kctx() {
    [[ "$1 $2" == "runtime override" && "$MOCK_OVERRIDE_ACTIVE" == 1 ]] || return 1
    print -r -- /run/user/1000/kctx/selection.yaml:/run/user/1000/kctx/view.yaml
}

__test_direnv() {
    case "$1" in
        reload) return "$MOCK_DIRENV_RELOAD_STATUS" ;;
        export) print -r -- "$MOCK_DIRENV_EXPORT" ;;
        *) return 1 ;;
    esac
}

KCTX_BIN=__test_kctx
KCTX_DIRENV_BIN=__test_direnv
TMUX=1
source /home/decoder/dev/dotfiles/scripts/__kctx_zsh_hook.zsh

print "=== pane override release ==="

KUBECONFIG=/from/envrc
MOCK_OVERRIDE_ACTIVE=0
__kctx_apply_pane_override
is "inactive hook preserves direnv before any override" "$KUBECONFIG" /from/envrc

MOCK_OVERRIDE_ACTIVE=1
__kctx_apply_pane_override
is "active override publishes the pane pair" "$KUBECONFIG" \
    /run/user/1000/kctx/selection.yaml:/run/user/1000/kctx/view.yaml

MOCK_OVERRIDE_ACTIVE=0
MOCK_DIRENV_EXPORT='export KUBECONFIG=/from/current/envrc'
__kctx_apply_pane_override
is "release restores the current direnv KUBECONFIG" "$KUBECONFIG" /from/current/envrc

MOCK_OVERRIDE_ACTIVE=1
__kctx_apply_pane_override
MOCK_OVERRIDE_ACTIVE=0
MOCK_DIRENV_EXPORT=
MOCK_DIRENV_RELOAD_STATUS=1
__kctx_apply_pane_override
is "release leaves KUBECONFIG unset without direnv" "${+KUBECONFIG}" 0

print "\n$pass passed, $fail failed"
(( fail == 0 ))
