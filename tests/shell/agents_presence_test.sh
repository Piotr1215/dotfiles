#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$HOME/dev/dotfiles/scripts/__agents_presence.sh"
COMPLETION="$HOME/dev/dotfiles/.zsh/completions/_snd"
T=$(mktemp -d)
BIN="$T/bin"
CACHE="$T/presence.tsv"
mkdir -p "$BIN"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

now_ms() { date +%s%3N; }

# Stub for the nats CLI. Emits the beats in $STUB_BEATS and exits, which ends
# the tail pipeline the same way a dropped connection would.
cat > "$BIN/nats" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_BEATS"
EOF
chmod +x "$BIN/nats"

beat() { printf '{"agent_id":"%s","name":"%s","group":"%s","host":"%s","ts":%s}' "$1" "$2" "$3" "$4" "$5"; }

run_tail() {
    NATS_BIN="$BIN/nats" \
    AGENTS_PRESENCE_CACHE="$CACHE" \
    AGENTS_PRESENCE_TTL_MS="${TTL:-30000}" \
    STUB_BEATS="$1" \
    "$SCRIPT" --tail
}

read_mode() {
    AGENTS_PRESENCE_CACHE="$CACHE" \
    AGENTS_PRESENCE_TTL_MS="${TTL:-30000}" \
    "$SCRIPT" "$1"
}

echo "== a tail turns beats into a roster =="
NOW=$(now_ms)
run_tail "$(beat codex-8b0ec1cf codex status serval "$NOW")
$(beat klod-d8f9ba83 klod status serval "$NOW")
$(beat scribe-11111111 scribe docs mac "$NOW")"

if [[ $(wc -l < "$CACHE") -eq 3 ]]; then ok "one row per agent"
else bad "one row per agent (got $(wc -l < "$CACHE"))"; fi

groups=$(read_mode --groups)
if [[ "$groups" == $'docs\nstatus' ]]; then ok "groups are distinct and live"
else bad "groups are distinct and live (got: ${groups//$'\n'/,})"; fi

agents=$(read_mode --agents)
if [[ "$agents" == $'codex\nklod\nscribe' ]]; then ok "agents are distinct and live"
else bad "agents are distinct and live (got: ${agents//$'\n'/,})"; fi

echo "== the newest beat wins, not the first =="
rm -f "$CACHE"
NOW=$(now_ms)
run_tail "$(beat codex-8b0ec1cf codex status serval "$NOW")
$(beat codex-8b0ec1cf codex triage serval "$((NOW + 10000))")"
if [[ $(wc -l < "$CACHE") -eq 1 ]]; then ok "a rebeat updates in place"
else bad "a rebeat updates in place"; fi
if [[ "$(read_mode --groups)" == "triage" ]]; then ok "the group follows the newest beat"
else bad "the group follows the newest beat"; fi

echo "== an expired beat is dropped, never offered =="
NOW=$(now_ms)
printf '%s\t%s\t%s\t%s\t%s\n' "ghost-deadbeef" "ghost" "nats" "serval" "$((NOW - 60000))" > "$CACHE"
printf '%s\t%s\t%s\t%s\t%s\n' "live-cafe1234" "live" "status" "serval" "$NOW" >> "$CACHE"
groups=$(read_mode --groups)
if [[ "$groups" == "status" ]]; then ok "readers filter past the TTL"
else bad "readers filter past the TTL (got: ${groups//$'\n'/,})"; fi

echo "== a tail prunes what it inherits =="
NOW=$(now_ms)
run_tail "$(beat live-cafe1234 live status serval "$NOW")"
if ! grep -q ghost "$CACHE"; then ok "the expired row leaves the cache file"
else bad "the expired row leaves the cache file"; fi
if grep -q live "$CACHE"; then ok "the live row survives the prune"
else bad "the live row survives the prune"; fi

echo "== an empty bus reports empty, not stale =="
rm -f "$CACHE"
if [[ -z "$(read_mode --groups)" ]]; then ok "no cache yields no groups"
else bad "no cache yields no groups"; fi
NOW=$(now_ms)
printf '%s\t%s\t%s\t%s\t%s\n' "ghost-deadbeef" "ghost" "nats" "serval" "$((NOW - 60000))" > "$CACHE"
if [[ -z "$(read_mode --agents)" ]]; then ok "an unfed cache yields no agents"
else bad "an unfed cache yields no agents"; fi

echo "== --list is readable =="
NOW=$(now_ms)
printf '%s\t%s\t%s\t%s\t%s\n' "codex-8b0ec1cf" "codex" "status" "serval" "$((NOW - 4000))" > "$CACHE"
listing=$(read_mode --list)
if [[ "$listing" == *"codex"* && "$listing" == *"status"* && "$listing" == *"serval"* ]]; then
    ok "the listing names agent, group and host"
else
    bad "the listing names agent, group and host"
fi
if grep -qE '\b[0-9]+s$' <<<"$listing"; then ok "the listing ages each beat"
else bad "the listing ages each beat"; fi

echo "== the completion reads the live roster =="
# The header explains why DuckDB went away, so only executable lines count.
if ! grep -vE '^\s*#' "$COMPLETION" | grep -q duckdb; then ok "no DuckDB query remains"
else bad "no DuckDB query remains"; fi
if grep -qF '__agents_presence.sh' "$COMPLETION"; then ok "names come from the helper"
else bad "names come from the helper"; fi
for dead in --exclude --pane --list-groups --list-agents --watch --kill --timeout; do
    if grep -qF -- "$dead" "$COMPLETION"; then
        bad "retired flag $dead is still offered"
    fi
done
if grep -qF -- '-g[Broadcast to a group]' "$COMPLETION"; then ok "only the flags snd parses remain"
else bad "only the flags snd parses remain"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
