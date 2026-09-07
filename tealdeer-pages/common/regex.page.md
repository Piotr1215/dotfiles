# regex

> Python re against POSIX ERE and vim. Full page: ~/dev/dotfiles/docs/python-regex.md

- Lazy quantifier, Python only:

`a*?`

- ERE has no lazy form and does not error, it reads a*? as (a*)? and matches a bare b:

`/usr/bin/grep -oE 'a*?b'`

- Digit class, Unicode by default in Python:

`\d`

- Digit class in GNU grep -E, where \d is a literal d:

`[[:digit:]]`

- Restrict \d \w \s to ASCII:

`re.findall(r"\d", s, re.ASCII)`

- Word boundary in Python:

`\b`

- Word boundary in vim and grep -E, in Python \< is a literal less-than:

`\<word\>`

- Lookahead and lookbehind, Python only:

`(?=x) (?!x) (?<=x) (?<!x)`

- Lookbehind must be fixed width, equal-length branches are allowed:

`(?<=ab|cd)x`

- Set the match start or end, vim only, in Python capture it and read .start(1):

`\zs \ze`

- Python rejects these as bad escape:

`\z \zs \ze \K`

- End of string, unlike $ it does not match before a trailing newline:

`a\Z`

- POSIX class inside brackets, in Python this is the set [:alph] plus a FutureWarning:

`[a-zA-Z] not [[:alpha:]]`

- Backspace character, not a boundary:

`[\b]`

- Inline flags, the global form is only legal at the pattern start:

`(?i) (?m) (?s) (?x) (?a)`

- Scoped flag, on and off:

`(?i:x) (?-i:x)`

- Named group, its backreference, and its substitution:

`(?P<n>x) (?P=n) \g<n>`

- Non-capturing, atomic, possessive:

`(?:x) (?>x) x*+`

- Variable-width lookbehind, \K and \p properties, via the third-party module:

`import regex`

- The interactive grep here is ugrep, which takes \d and rejects \1:

`/usr/bin/grep -E for GNU behavior`

- tmux-pane-regex compiles with DOTALL, so .* walks across lines, use this for one line:

`^[^\n]*word`

- \W and \s match newlines too, so a trailing \W* runs onto the next line, this stays put:

`^comm[^\w\n]*`

- Stop before a character without consuming it, negated class or lookahead, both cross lines unless you add \n:

`^word[^:\n]*` or `^word.*(?=:)`

- \W never hops, it matches zero characters inside a word, finish the word first:

`^wo\w*\W`

- Back to the nearest delimiter, vim vF/ and vT/, the negated class picks the nearest and \n keeps it on the line:

`^/[^/\n]*word` or `^[^/\n]*word`

- Select the whitespace-delimited token, like viW:

`^\S*word\S*`

- Reach one word further back:

`^(?:\S+ +)\S*word`
