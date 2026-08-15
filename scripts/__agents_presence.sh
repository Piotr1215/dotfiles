#!/usr/bin/env bash
# Live roster of the agents comms bus, for shell completion and quick checks.
#
# snd's completion used to read the `agents` table in agents.duckdb. That table
# stopped being written when agents-mcp-server a43d56b dropped DuckDB for an
# in-memory registry plus NATS presence, so TAB kept offering the groups that
# happened to be registered on 2026-04-24 (nats, test, mcp) months after they
# were gone. Stale names on a shared bus are worse than none: a broadcast to a
# group nobody is in publishes into the void and looks like it worked.
#
# The live view is the presence stream itself, the same source registry.ts uses
# to learn remote peers. Beats carry name, group, host and ts, one per agent
# every 10s, with peers expiring after 30s. A completion cannot sample that
# inside a TAB press, so --tail holds the subscription and maintains a cache the
# readers hit instantly. An expired row is dropped rather than shown, so the
# picker goes empty when the bus is empty instead of lying.
set -eo pipefail

NATS_URL="${AGENTS_NATS_URL:-nats://nats-nats-tailscale.tail165ec.ts.net:4222}"
NATS_BIN="${NATS_BIN:-$HOME/.local/bin/nats}"
CACHE="${AGENTS_PRESENCE_CACHE:-$HOME/.cache/agents-presence.tsv}"
# Mirrors DEFAULT_PEER_TTL_MS in agents-mcp-server src/nats.ts. Keep them equal:
# a shorter TTL hides agents the server still considers present, a longer one
# offers targets it has already forgotten.
TTL_MS="${AGENTS_PRESENCE_TTL_MS:-30000}"

usage() {
    cat <<'EOF'
__agents_presence.sh - live roster of the agents comms bus

usage:
  --tail            hold the agents.presence subscription and maintain the
                    cache. Long-running; this is what agents-presence.service
                    executes.
  --groups          print live group names, one per line
  --agents          print live agent names, one per line
  --list            print live agents as name/group/host/age
  --sample [secs]   one-shot sample into the cache without the tailer running.
                    Needs a full heartbeat interval (default 11s) to see every
                    agent.
  --status          report whether the roster is being fed
  --help

env:
  AGENTS_NATS_URL          bus url
  AGENTS_PRESENCE_CACHE    cache path
  AGENTS_PRESENCE_TTL_MS   how long a beat counts as live (default 30000)
EOF
}

now_ms() { date +%s%3N; }

# Rows still inside the TTL. Everything downstream reads through this, so an
# unfed cache yields nothing instead of yesterday's roster.
live_rows() {
    [[ -f "$CACHE" ]] || return 0
    awk -F'\t' -v now="$(now_ms)" -v ttl="$TTL_MS" \
        'NF >= 5 && $5 ~ /^[0-9]+$/ && (now - $5) <= ttl' "$CACHE"
}

require_deps() {
    local missing=()
    [[ -x "$NATS_BIN" ]] || command -v nats >/dev/null 2>&1 || missing+=("nats")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "__agents_presence.sh: missing ${missing[*]}" >&2
        exit 2
    fi
    [[ -x "$NATS_BIN" ]] || NATS_BIN="$(command -v nats)"
}

# Subscribe and keep the cache current. `duration` empty means forever.
collect() {
    local duration="$1"
    require_deps
    mkdir -p "$(dirname "$CACHE")"

    local -a sub_cmd=("$NATS_BIN" --server "$NATS_URL" sub agents.presence --raw)
    [[ -n "$duration" ]] && sub_cmd=(timeout "$duration" "${sub_cmd[@]}")

    # The read loop is the tail of a pipeline, so it runs in a subshell. Every
    # use of the roster map lives inside that same brace group; pulling any of
    # it out would silently operate on an empty copy.
    "${sub_cmd[@]}" \
        | jq -r --unbuffered \
            '[.agent_id // "", .name // "", .group // "default", .host // "?", .ts // 0] | @tsv' \
        | {
            declare -A roster=()
            id=""; name=""; group=""; host=""; ts=""

            # Preload, so a restart does not blank the picker for a full
            # heartbeat interval while the first beats arrive.
            while IFS=$'\t' read -r id name group host ts; do
                [[ -n "$id" ]] && roster["$id"]="${name}"$'\t'"${group}"$'\t'"${host}"$'\t'"${ts}"
            done < <(live_rows)

            flush() {
                local now="$1" tmp key rname rgroup rhost rts
                tmp="$(mktemp "${CACHE}.XXXXXX")"
                for key in "${!roster[@]}"; do
                    IFS=$'\t' read -r rname rgroup rhost rts <<<"${roster[$key]}"
                    if (( now - rts > TTL_MS )); then
                        unset 'roster[$key]'
                        continue
                    fi
                    printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$rname" "$rgroup" "$rhost" "$rts" >>"$tmp"
                done
                sort -o "$tmp" "$tmp"
                mv -f "$tmp" "$CACHE"
            }

            while IFS=$'\t' read -r id name group host ts; do
                [[ -z "$id" || -z "$ts" ]] && continue
                roster["$id"]="${name}"$'\t'"${group}"$'\t'"${host}"$'\t'"${ts}"
                flush "$(now_ms)"
            done
            # A sample that heard nothing must still expire what it inherited.
            flush "$(now_ms)"
        }
}

case "${1:-}" in
    --tail)
        collect ""
        ;;
    --sample)
        collect "${2:-11}s"
        ;;
    --groups)
        live_rows | cut -f3 | sort -u
        ;;
    --agents)
        live_rows | cut -f2 | sort -u
        ;;
    --list)
        now="$(now_ms)"
        live_rows | awk -F'\t' -v now="$now" \
            'BEGIN { printf "%-16s %-12s %-10s %s\n", "AGENT", "GROUP", "HOST", "AGE" }
             { printf "%-16s %-12s %-10s %ds\n", $2, $3, $4, int((now - $5) / 1000) }'
        ;;
    --status)
        count="$(live_rows | wc -l)"
        if [[ "$count" -gt 0 ]]; then
            echo "roster: $count live on $NATS_URL"
        elif systemctl --user is-active --quiet agents-presence.service 2>/dev/null; then
            echo "roster: empty, tailer running (nobody is registered)"
        else
            echo "roster: empty, tailer not running (systemctl --user start agents-presence)" >&2
            exit 1
        fi
        ;;
    --help | -h | "")
        usage
        ;;
    *)
        echo "__agents_presence.sh: unknown argument '$1'" >&2
        usage >&2
        exit 1
        ;;
esac
