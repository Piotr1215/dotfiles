---
name: zledit-extender
description: Creates actions and previewers for zledit plugin. Triggers on "zsh jumper", "zsh actions", "zsh previews", "add action", "add previewer"
---

# zledit Extender

Creates custom actions and previewers for the zledit plugin.

## When to Use

- User asks to add an action to zledit
- User asks to add a previewer to zledit
- User mentions "zsh jumper" with customization intent

## Repository Location

`/home/decoder/dev/zledit`

## Action Script Interface

Actions manipulate the command line buffer. Create bash scripts with:

**Input:**
- `$1` = selected token text
- `$2` = token index (1-based)
- `ZJ_BUFFER` = current command line
- `ZJ_POSITIONS` = newline-separated start positions
- `ZJ_WORDS` = newline-separated tokens
- `ZJ_CURSOR` = current cursor position
- `ZJ_PICKER` = active picker (fzf, fzf-tmux, sk)

**Output:**
- Exit 0 + stdout = apply as new buffer
- Exit non-zero = cancel, no change
- Cursor defaults to token position
- Override with `CURSOR:N` as last line (only when needed)

**Template:**
```bash
#!/usr/bin/env bash
set -eo pipefail

TOKEN="$1"
INDEX="$2"

[[ -z "$TOKEN" || -z "$INDEX" || -z "$ZJ_BUFFER" || -z "$ZJ_POSITIONS" ]] && exit 1

IFS=$'\n' read -r -d '' -a positions <<< "$ZJ_POSITIONS" || true
pos="${positions[$((INDEX - 1))]}"
[[ -z "$pos" ]] && exit 1

# Transform token
new_token="$TOKEN"  # Your transformation here

# Replace in buffer
end_pos=$((pos + ${#TOKEN}))
echo "${ZJ_BUFFER:0:$pos}${new_token}${ZJ_BUFFER:$end_pos}"
# Optional: echo "CURSOR:N" for custom cursor position
```

## Previewer Script Interface

Previewers show context in fzf preview window.

**Input:**
- `$1` = token to preview (index prefix stripped)

**Output:**
- Write preview content to stdout

## TOML Config Format

Users point to config via: `zstyle ':zledit:' config /path/to/config.toml`

```toml
[[actions]]
binding = 'ctrl-u'
description = 'upper'
script = '/path/to/script.sh'

[[previewers]]
pattern = '^https?://'
description = 'URL preview'
script = '/path/to/preview.sh'
```

## Workflow

1. User describes what transformation they want
2. Create script following template above
3. Place in `~/.config/zledit/scripts/`
4. Make executable: `chmod +x script.sh`
5. Add to `~/.config/zledit/config.toml`

## Reference Examples

See `/home/decoder/dev/zledit/examples/` for sample scripts

## Common Patterns

**Replace token:** Standard pattern in template above

**Delete token:** Output buffer without the token (no new_token)

**Wrap token:** Insert prefix/suffix, use `CURSOR:N` to position inside

**Custom cursor:** Only use `CURSOR:N` when position differs from token start

## Introspection

List all registered config, actions, and previewers:

```bash
zledit-list
```

Shows: plugin dir, config path, picker, binding, all actions with scripts, all previewers with scripts.

## Key Points

- Scripts can live anywhere (user's choice)
- User-defined bindings override built-in defaults
- Previewers match in order, first match wins
- Paths starting with `~` expand to `$HOME`
- Test manually: `export ZJ_BUFFER="..."; ./script.sh "token" "2"`
- Use `zledit-list` to see what's registered
