#!/usr/bin/env bash

set -eo pipefail

# Create a temporary directory for our fzf wrapper
WRAPPER_DIR=$(mktemp -d)

# Create an fzf wrapper that filters out links and adds tag browser keybinding
cat > "$WRAPPER_DIR/fzf" << 'EOF'
#!/usr/bin/env bash
# Filter out lines starting with [Link to before passing to real fzf
# Add keybinding to launch tag browser
grep -v '^\[Link to' | /usr/local/bin/fzf \
    --bind "ctrl-g:execute(~/dev/dotfiles/scripts/__snippet_tag_browser.sh)+abort" \
    --header " ctrl-g: browse by tag" \
    "$@"
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