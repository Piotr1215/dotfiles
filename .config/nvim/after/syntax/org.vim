" Minimal org highlighting for the reminder agenda (remind agenda). Neovim
" detects .org but ships no syntax; this covers headings, timestamps and
" property lines, nothing more.
if exists('b:current_syntax') | finish | endif

syntax match orgComment    /^#.*/
syntax match orgSection    /^\* .*/
syntax match orgHeading    /^\*\* .*/ contains=orgStamp
syntax match orgStamp      /<[^>]*>/ contained
syntax match orgProperty   /^\s\+:[a-z]\+:/ nextgroup=orgPropValue
syntax match orgPropValue  /.*/ contained
syntax match orgId         /^\s\+:id:.*/

highlight default link orgComment   Comment
highlight default link orgSection   Title
highlight default link orgHeading   Statement
highlight default link orgStamp     Number
highlight default link orgProperty  Identifier
highlight default link orgPropValue String
highlight default link orgId        Comment

let b:current_syntax = 'org'
