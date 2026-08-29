# ddgx

> Terminal DuckDuckGo search with readable page extracts.
> Plain text searches the web. `@` searches Claude Code docs. `?` asks Perplexity.

- Search fresh DuckDuckGo results in Stage 1:

`type a plain query, pause, then press Enter`

- Search literal words inside the returned pages in Stage 2:

`codex agent`

- Search one exact phrase inside the returned pages:

`"codex agent"`

- Use an extended regular expression in Stage 2:

`/{{ERE pattern}}/`

- Match one whole word:

`/\bJibrail\b/`

- Match the whole line containing one word:

`/^.*\bJibrail\b.*$/`

- Match `bookmarks`, one literal space, then any word:

`/bookmarks \w+/`

- Generic ERE for one word, one literal space, then any word:

`/{{word}} \w+/`

- Match either of two whole words:

`/\b(codex|claude)\b/`

- Open selected page notes in Neovim with matches in quickfix:

`Ctrl + e`

- Move through ddgx matches in Neovim:

`Ctrl + g, then n`

`Ctrl + g, then p`

- Open or hide the quickfix view from the normal Neovim config:

`<leader>xq`
