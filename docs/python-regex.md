# python-regex(7)

## NAME

Python `re` against POSIX ERE and vim. What each dialect has, what it silently reinterprets, and what it rejects.

## QUICK ANSWER

Python `re` is PCRE-shaped: lazy quantifiers, lookaround, named groups, backreferences. POSIX ERE has none of those, only alternation, grouping, `?` `*` `+` `{n,m}`, and bracket expressions. Vim is a third dialect with its own escaping and two features neither of the others has, `\zs` and `\ze`. Every ERE row below is GNU grep 3.11, which already ships extensions past the standard.

## DIALECT MAP

| Need | Python `re` | GNU `grep -E` | vim |
| --- | --- | --- | --- |
| Lazy | `a*?` | none | `a\{-}` |
| Possessive, atomic | `a*+`, `(?>a*)` | none | none |
| Digit, word, space | `\d` `\w` `\s` | `\w` `\s`, no `\d` | `\d` `\w` `\s` |
| Word boundary | `\b` | `\<` `\>` `\b` | `\<` `\>` |
| Non-capturing group | `(?:x)` | none, every group captures | `\%(x\)` |
| Named group | `(?P<n>x)`, `(?P=n)`, `\g<n>` in sub | none | none |
| Backreference | `\1` | `\1` | `\1` |
| Lookahead | `(?=x)` `(?!x)` | none | `\(x\)\@=` |
| Lookbehind | `(?<=x)` `(?<!x)`, fixed width | none | `\@<=`, variable width |
| Set match start, end | capture group, `.start(1)` | none | `\zs` `\ze` |
| Conditional | `(?(1)yes\|no)` | none | none |
| Inline case fold | `(?i)` at pattern start only | `-i` | `\c` anywhere |
| Comments, whitespace | `re.VERBOSE` | none | none |

## TRAPS

`\<` and `\>` compile in Python and mean a literal `<` and `>`. Python treats a backslash before punctuation as that punctuation, so a vim word boundary becomes a bracket match and fails quietly. Use `\b`.

`\z`, `\zs`, `\ze`, `\K` do not exist: `bad escape \z at position 0`. The end-of-string anchor is `\Z`. There is no way to set the match start after the fact; capture the part you want and read `.start(1)`.

`$` matches before a trailing newline, `\Z` does not. On `"a\n"`, `a$` matches and `a\Z` does not.

`[[:alpha:]]` is not a POSIX class in Python. It parses as the character set `[:alph]` with a `FutureWarning: Possible nested set`, and matched nothing on `"ab: [x]"`. Write `[a-zA-Z]` or `\w`.

`[\b]` is a backspace character, not a boundary. The boundary only means boundary outside a bracket.

`\d` is Unicode by default and matches `٢`. Pass `re.ASCII` when you mean `[0-9]`.

`(?i)` must sit at the very start of the pattern. Mid-pattern raises `global flags not at the start of the expression`. Scoped `(?i:x)` works anywhere, and `(?-i:x)` turns the flag back off for that group.

Lookbehind must be fixed width. `(?<=ab|cd)x` is fine because both branches are two characters. `(?<=a+)x` raises `look-behind requires fixed-width pattern`.

`\W` and `\s` include `\n`, so a trailing `\W*` walks off the end of the line and swallows the next line's indent. `^comm\W*` against `run comm.` selects `comm.` plus the newline. Use `[^\w\n]*` to stay on one line, or `\S*` when you meant the token. A negated class carries the same hazard and needs no `DOTALL` to do it: with no colon on the line, `^comma[^:]*` selected `command here\nnext`. Write `[^:\n]*`.

`.` excludes `\n` unless `re.DOTALL`, and `^` `$` are string-wide unless `re.MULTILINE`. Under `DOTALL` a stray `.*` walks across lines. Use `[^\n]*` when you mean the rest of one line.

ERE has no lazy quantifier and does not error on `a*?`, it reads it as `(a*)?`. GNU grep matched a bare `ab` against `a*?b`. The pattern looks like it worked, which is why the bug survives.

The interactive `grep` on this machine is ugrep 7.8.4, a fourth dialect. It accepts `\d` where GNU grep reads a literal `d`, and it rejects a backreference `\1` that GNU grep accepts. Call `/usr/bin/grep` when the dialect matters.

## FLAGS

| Flag | Inline | Effect |
| --- | --- | --- |
| `re.IGNORECASE` | `(?i)` | Case fold |
| `re.MULTILINE` | `(?m)` | `^` `$` match at every line |
| `re.DOTALL` | `(?s)` | `.` matches `\n` |
| `re.VERBOSE` | `(?x)` | Ignore whitespace, allow `#` comments |
| `re.ASCII` | `(?a)` | `\d` `\w` `\s` become ASCII only |

## WHEN PYTHON IS NOT ENOUGH

The third-party `regex` module (2026.4.4, installed) is a drop-in with variable-width lookbehind, `\K`, and `\p{Lu}` property classes. `(?<=a+)x`, `a\Kx`, and `\p{Lu}` all work there and all fail in `re`.

## IN TMUX-PANE-REGEX

The pane picker compiles queries with `MULTILINE | DOTALL` and `IGNORECASE`, so every trap above applies, `.*` crossing lines most of all.

| Query | Selection |
| --- | --- |
| `^word` | Whole logical line, locator highlighted |
| `^\S*word\S*` | The whitespace-delimited token, vim `viW` |
| `^(?:\S+ +)\S*word` | One word further back |
| `^/[^/\n]*word` | Back to the nearest `/`, vim `vF/`, drop the leading `/` for `vT/` |
| `^[^\n]*word` | Back to line start, never past it |
| `^\Cword` | Case-sensitive, tool flag, not `re` syntax |
| `^word$$` | Through the end of that logical line |
| `^word\ss` | Through the first `.`, `?`, or `!` |

## SEE ALSO

`man 7 regex` for POSIX, `:help pattern` for vim, https://docs.python.org/3/library/re.html for the reference.

Verified on Python 3.12.3, GNU grep 3.11, ugrep 7.8.4, regex 2026.4.4, 2026-09-05.
