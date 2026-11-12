#!/usr/bin/env bash
set -eo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export TEST_DIR="$tmp" PATH="$tmp/bin:$PATH"
cat > "$tmp/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
if [[ $2 == cpthost ]]; then
  n=$(cat "$TEST_DIR/checks" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$TEST_DIR/checks"
  [[ ${MEETING_AT:-0} == "$n" ]]
else
  [[ ${ZOOM_RUNNING:-0} == 1 ]]
fi
STUB
cat > "$tmp/bin/dpkg-query" <<'STUB'
#!/usr/bin/env bash
if [[ -e $TEST_DIR/installed ]]; then printf '%s' "${AFTER:-1}"; else printf 1; fi
STUB
cat > "$tmp/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_DIR/calls"
[[ ${FAIL:-none} != "$3" ]] || exit 1
[[ $3 != install ]] || touch "$TEST_DIR/installed"
STUB
cat > "$tmp/bin/notify-send" <<'STUB'
#!/usr/bin/env bash
echo notify >> "$TEST_DIR/notifications"
STUB
cat > "$tmp/bin/nohup" <<'STUB'
#!/usr/bin/env bash
echo launch >> "$TEST_DIR/launch"
STUB
chmod +x "$tmp/bin/"*
run_case() {
  rm -f "$tmp/checks" "$tmp/calls" "$tmp/installed" "$tmp/launch" "$tmp/notifications"
  env "$@" bash "$root/scripts/__zoom_autoupdate.sh" > "$tmp/out" 2>&1
}
run_case MEETING_AT=1
rg -q 'skipped: meeting active;' "$tmp/out"
[[ ! -e $tmp/calls ]]
run_case MEETING_AT=2
rg -q 'meeting active after update' "$tmp/out"
[[ $(wc -l < "$tmp/calls") == 1 ]]
run_case
rg -q 'already up to date; old=1 new=1' "$tmp/out"
[[ $(wc -l < "$tmp/calls") == 2 ]]
run_case AFTER=2 ZOOM_RUNNING=1 MEETING_AT=3
rg -q 'old=1 new=2' "$tmp/out"
[[ ! -e $tmp/launch ]]
if run_case FAIL=update; then exit 1; fi
[[ $(wc -l < "$tmp/notifications") == 1 ]]
echo 'zoom autoupdate tests passed'
