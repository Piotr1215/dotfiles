#!/usr/bin/env bash

set -eo pipefail

# Create a temporary directory for our fzf wrapper
WRAPPER_DIR=$(mktemp -d)

# Create an fzf wrapper that filters out links, lays the snippets out in
# columns and adds a tag browser keybinding.
#
# WHY THE AWK: pet's Format string ("[$description]: $command $tags") only
# concatenates. Column = 40 in pet's config does nothing on this path, so the
# lines arrive between 39 and 381 characters long and the command sits at a
# different offset on every row, usually off the right edge behind the prose.
# The awk pads the description to a fixed width and truncates both fields, so
# the command always starts in the same place.
#
# WHY THE TAB: pet maps the line it gets back to a snippet by exact string
# match (cmd/util.go filter()), so a reformatted line returns an empty command.
# The original line rides along after a tab, fzf shows and searches only field
# one (--with-nth=1), and cut hands the untouched original back to pet.
#
# WHY --exact: the default fuzzy match turned "fmt" into 58 of 117 rows by
# finding f, m and t scattered anywhere in the line. Exact substring matching
# returns the one row that actually runs fmt. A leading ' still forces fuzzy.
cat > "$WRAPPER_DIR/fzf" << 'EOF'
#!/usr/bin/env bash
cols=$( { tput cols; } 2>/dev/null < /dev/tty || echo 180 )
desc_w=46
cmd_w=$(( cols - desc_w - 8 ))
[ "$cmd_w" -lt 30 ] && cmd_w=30

# One line per pick, most recent last. The whole pet line is the key, so an
# edited description simply starts a fresh streak rather than crediting the
# wrong snippet.
state="${XDG_STATE_HOME:-$HOME/.local/state}/pet-recency"
mkdir -p "${state%/*}"
[ -f "$state" ] || : > "$state"

# Sort key first, stripped again before fzf sees the line: recently picked
# snippets ascend, everything else keeps file order behind them. fzf falls back
# to input order for equally good matches, so recency also breaks ties mid-query.
selected=$(grep -v '^\[Link to' | awk -v D="$desc_w" -v C="$cmd_w" -v STATE="$state" '
BEGIN {
    n = 0
    while ((getline line < STATE) > 0) rank[line] = ++n
}
{
    orig = $0
    i = index($0, "]: ")
    if (substr($0, 1, 1) == "[" && i > 0) {
        desc = substr($0, 2, i - 2)
        rest = substr($0, i + 3)
    } else {
        desc = $0
        rest = ""
    }
    if (length(desc) > D) desc = substr(desc, 1, D - 1) "…"
    if (length(rest) > C) rest = substr(rest, 1, C - 1) "…"
    key = (orig in rank) ? (1000000 - rank[orig]) : (2000000 + NR)
    printf "%d\t%-*s  %-*s\t%s\n", key, D, desc, C, rest, orig
}' | sort -t$'\t' -k1,1n -s | cut -f2- | /usr/local/bin/fzf \
    --exact \
    --delimiter=$'\t' \
    --with-nth=1 \
    --bind "ctrl-g:execute(~/dev/dotfiles/scripts/__snippet_tag_browser.sh)+abort" \
    --bind "ctrl-f:transform-query(printf %s {q} | sed -e \"s/^'//;t\" -e \"s/^/'/\")" \
    --header " ctrl-g: browse by tag   |   ctrl-f: fuzzy (for typos)" \
    "$@")

[ -n "$selected" ] || exit 0

original=$(printf '%s\n' "$selected" | cut -f2-)
printf '%s\n' "$original" >> "$state"
tail -n 500 "$state" > "$state.tmp" && mv "$state.tmp" "$state"

printf '%s\n' "$original"
EOF

chmod +x "$WRAPPER_DIR/fzf"

# Add our wrapper to PATH before the real fzf
export PATH="$WRAPPER_DIR:$PATH"

# Now pet will use our wrapped fzf!
RESULT=$(pet search)

# Clean up
rm -rf "$WRAPPER_DIR"

# Output the result for zsh to capture
if [ -n "$RESULT" ]; then
    echo "$RESULT"
fi
