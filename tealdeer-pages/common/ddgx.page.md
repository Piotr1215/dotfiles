# ddgx

> Terminal DuckDuckGo search with readable page extracts, on one screen.
> Plain text searches the web. `@` searches Claude Code docs. `?` asks Perplexity.

- Search the web: type, then pause:

`{{query}}`

- Ask Perplexity, at a harder preset with `??`, then send it:

`? {{question}}, then Enter`

- Open the selected result, or send a query the rows do not answer yet:

`Enter`

- Open concise help, then return with `q`:

`F1`

- Switch the box to the page text and back:

`Ctrl + f`

- Search literal words inside the returned pages, after `Ctrl + f`:

`codex agent`

- Search one exact phrase inside the returned pages:

`"codex agent"`

- Use an extended regular expression inside the pages:

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
