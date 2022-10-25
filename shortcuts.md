## Shell

Ctrl + U            – remove from the cursor to the start of the line.
Ctrl + K            – cut from the cursor to the end of the line.
Ctrl + W            – cut from the cursor to the start of the preceding word.<- LEFT
Ctrl + Y            - paste last copied word from the clipboard
Ctrl + q            - when a command is already typed, move it to buffer, clear command line and execute another one before
Alt  + D            – "remove from the cursor to the end of the next word."
Ctrl + L            – clear the terminal.
Ctrl + A            - go to the beginning of the line
Ctrl + E            - go to the end of the line
Alt  + B            - go back one word
Alt  + F            - go forward one word
Ctrl + XX           - switch between beginning of the line and current position
Ctrl + XE           - edit current command in default editor
dult  + T            - swap the current word with the previous word
Ctrl + T            - swap 2 characters places
Alt  + .            - repeat last argument of previous command, same as !$
Ctrl + Shift + _    - undo last keystroke in command
!*                  - all arguments of previous function except first
!$                  - last argument of previous call

## Tmux
Ctrl +b, Alt + 1    - change panes to vertical position
Ctrl +b, Alt + 2    - change panes to horizontal position
Ctro +b, Ctrl + o   - swap panes 1:2 to 2:1
Ctrl +b [           - enter copy Mode

## Vim
"+yt                            - copy to clipboard till character (space in this case)
Ctro + n                        - does some crazy multi-cursor
Ctrl + u                        - go 1/4 screen up
Ctrl + d                        - go 1/4 screen down
Ctrl + f                        - go 1 screen up
Ctrl + b                        - go 1 screen down
z    + Enter                    - move line to the top of the screen
M                               - move to the middle of the screen
%                               - move to related closing item like ([<]) etc
sp                              - horizontal split
vsp                             - vertical split
:r !command                     - execute command and insert output below the cursor
Ctrl + 6                        - switch between buffers
:g/pattern/norm! @a             - excute macro stored in a registry over lines matching pattern
Ctrl + f                        - in command mode, edit list of previous commands
Ctro + a                        - increment number in normal mode
Ctrl + w + HJKL                 - move splits around
Ctrl + w + Ctrl + r             - Rotate splits
Ctrl + w + hjkl + Ctrl + w x    - Swap position of 2 panes. Navigate from the
                                  window to the one u want to swap with and hit x 
:echo maparg("<leader>ff", "n") - this will detect what mapping maps to~
q:                              - enter commands history
q/                              - enter search history

### Insert mode
Ctrl + y            - copy character from the line above
Ctrl + e            - copy character from the line below

### Plugins

#### Nvim Surround

    Old text                    Command         New text
--------------------------------------------------------------------------------
    surr*ound_words             ysiw)           (surround_words)
    *make strings               ys$"            "make strings"
    [delete ar*ound me!]        ds]             delete around me!
    remove <b>HTML t*ags</b>    dst             remove HTML tags
    'change quot*es'            cs'"            "change quotes"
    <b>or tag* types</b>        csth1<CR>       <h1>or tag types</h1>
    delete(functi*on calls)     dsf             function calls

## Tips $ Tricks

### How to modify multiple files

1. Record a macro
2. Load files to buffers: args pattern for files
3. Execute macro: argsdo normal@mw (where m is macro and w stands for write)
4. Write all buffers: wall

### How to convert decimal to binary

Conversion steps:
- Divide the number by 2.
- Get the integer quotient for the next iteration.
- Get the remainder for the binary digit.
- Repeat the steps until the quotient is equal to 0.

## Tmuxinator Layouts

The following layouts are supported:

even-horizontal
Panes are spread out evenly from left to right across the window.

even-vertical
Panes are spread evenly from top to bottom.

main-horizontal
A large (main) pane is shown at the top of the window and the remaining panes are spread from left to right in the leftover space at the bottom. Use the main-pane-height window option to specify the height of the top pane.

main-vertical
Similar to main-horizontal but the large pane is placed on the left and the others spread from top to bottom along the right. See the main-pane-width window option.

tiled
Panes are spread out as evenly as possible over the window in both rows and columns.

## Ranger

Command hints show up whenever a mapping has multiple continuations:
g for navigation and tabs
r for :open_with command
y for yank(copy)
d for cut/delete
p for paste
o for sort
. for filter_stack
z for changing settings
u for "undo"
M for linemode
+, -, = for setting access rights to files