# zsh

> Z shell shortcuts and special parameters

- Reference first argument of current command line (history expansion):

`!#:1`

- Reference last argument of current command line:

`!#:$`

- Perform text substitution on selected word:

`!#:1:s/from/to`

- Remove from cursor to start of line:

`Ctrl + U`

- Cut from cursor to end of line:

`Ctrl + K`

- Cut from cursor to start of preceding word:

`Ctrl + W`

- Copy command line content:

`Ctrl + Y`

- Move command to buffer and clear line:

`Ctrl + Q`

- Repeat previous argument:

`Ctrl + _`

- Remove from cursor to end of next word:

`Alt + D`

- Clear terminal:

`Ctrl + L`

- Go to beginning of line:

`Ctrl + A`

- Go to end of line:

`Ctrl + E`

- Go back one word:

`Alt + B`

- Go forward one word:

`Alt + F`

- Switch between beginning of line and current position:

`Ctrl + XX`

- Edit current command in default editor:

`Ctrl + XE`

- Swap the current word with previous word:

`Alt + T`

- Swap 2 characters places:

`Ctrl + T`

- Repeat last argument of previous command:

`Alt + .`

- Undo last keystroke in command:

`Ctrl + Shift + _`

- Execute command and open output in Neovim GPT chat:

`Ctrl + Alt + G`

- Previous command without parameters:

`!:0`

- Positional parameters from previous command:

`!:1 !:2 ...`

- Number of positional parameters:

`$#`

- All positional parameters (individually quoted):

`$@`

- All positional parameters (space-separated):

`$*`

- Last argument of previous command:

`$_`

- Exit status of last command:

`$?`

- Process ID of current shell:

`$$`

- Process ID of last background command:

`$!`

- Internal field separator:

`$IFS`

- Print to terminal without hitting enter:

`print -z "text"`

- Accept one word from autosuggestion:

`Ctrl + Right Arrow`

