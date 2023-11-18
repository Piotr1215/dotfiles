## Shell

| Keyboard Shortcut | Action |
| --- | --- |
| Ctrl + U | Remove from cursor to start of line |
| Ctrl + K | Cut from cursor to end of line |
| Ctrl + W | Cut from cursor to start of preceding word.<- LEFT |
| Ctrl + Y | Copy command line content |
| Ctrl + q | When a command is already typed, move it to buffer, clear command line and execute another one before |
| Alt + D | Remove from cursor to end of next word |
| Ctrl + L | Clear terminal |
| Ctrl + A | Go to beginning of line |
| Ctrl + E | Go to end of line |
| Alt + B | Go back one word |
| Alt + F | Go forward one word |
| Ctrl + XX | Switch between beginning of line and current position |
| Ctrl + XE | Edit current command in default editor |
| dult + T | Swap the current word with previous word |
| Ctrl + T | Swap 2 characters places |
| Alt + . | Repeat last argument of previous command, same as !$ |
| Ctrl + Shift + _ | Undo last keystroke in command |
| !*:1 !*:2 ... | Positional parameters from previous command |
| $# | Number of positional parameters passed to the shell script or function |
| $@ | All the positional parameters passed to the shell script or function, individually quoted |
| $\* | All the positional parameters passed to the shell script or function, as a single, space-separated string |
| $? | Exit status of the last executed command |

$$
- the process ID of the current shell.
$!                   - the process ID of the last executed background command.
$IFS                 - the internal field separator, used to separate words in a string.

Loop through a file:
while read -r cmd; do
  echo "Processing: $cmd"
  # Your code here
done < coms
---

## Tmux
Ctrl +b, Alt + 1    - change panes to vertical position
Ctrl +b, Alt + 2    - change panes to horizontal position
Ctro +b, Ctrl + o   - swap panes 1:2 to 2:1
Ctrl +b [           - enter copy Mode

---

| Command | Description |
| --- | --- |
| P | pastes text and replaces current buffer |
| p | pastes without replacing buffer |
| :h index | check what key is mapped to |
| verbose? |  |
| "+yt" | copy to clipboard till character (space in this case) |
| Ctro + n | does some crazy multi-cursor |
| Ctrl + u | go 1/4 screen up |
| Ctrl + d | go 1/4 screen down |
| Ctrl + f | go 1 screen up |
| Ctrl + b | go 1 screen down |
| z + Enter | move line to the top of the screen |
| M | move to the middle of the screen |
| % | move to related closing item like ([<]) etc |
| sp | horizontal split |
| vsp | vertical split |
| :r !command | execute command and insert output below the cursor |
| Ctrl + 6 | switch between buffers |
| :g/pattern/norm! @a | excute macro stored in a registry over lines matching pattern |
| Ctrl + f | in command mode, edit list of previous commands |
| Ctro + a | increment number in normal mode |
| Ctrl + w + HJKL | move splits around |
| Ctrl + w + Ctrl + r | Rotate splits |
| Ctrl + w + hjkl + Ctrl + w x | Swap position of 2 panes. Navigate from the window to the one u want to swap with and hit x |
| :echo maparg("<leader>ff", "n") | this will detect what mapping maps to~ |
| q: | enter commands history |
| q/ | enter search history |

### LSP

K twice enters the hover window so can copy from there etc

### Insert mode
Ctrl + y            - copy character from the line above
Ctrl + e            - copy character from the line below

---

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

---

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

---

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

---

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

---

## Moreutils

The moreutils tools

    chronic: runs a command quietly unless it fails
    combine: combine the lines in two files using boolean operations
    errno: look up errno names and descriptions
    ifdata: get network interface info without parsing ifconfig output
    ifne: run a program if the standard input is not empty
    isutf8: check if a file or standard input is utf-8
    lckdo: execute a program with a lock held
    mispipe: pipe two commands, returning the exit status of the first
    parallel: run multiple jobs at once
    pee: tee standard input to pipes
    sponge: soak up standard input and write to a file
    ts: timestamp standard input
    vidir: edit a directory in your text editor
    vipe: insert a text editor into a pipe
    zrun: automatically uncompress arguments to command

---

## Taskwarrior

Taskwarrior is a command-line task management program that provides various attributes and modifiers to adjust when and how tasks are displayed, acted upon, and due. Here's a list of the time-specific attributes/modifiers and their explanations:

1. **due:** The due date of a task. For example:
   ```
   task add Buy milk due:tomorrow
   ```

2. **wait:** The date or duration to wait until the task becomes active (or 'pending'). Until that time, the task is in a 'waiting' status and doesn't show up in the default report. For example:
   ```
   task add Buy bread wait:2days
   ```

3. **until:** The expiration date of the task. If a task isn't completed before its `until` date, it'll be automatically deleted. For example:
   ```
   task add Buy chocolate until:2023-09-01
   ```

4. **scheduled:** The date or time you intend to start the task. It's informational and doesn't affect the status of the task. For example:
   ```
   task add Read a book scheduled:next week
   ```

5. **recur:** How frequently a recurring task should be created. For example:
   ```
   task add Pay rent due:1st recur:monthly
   ```
   This will create a recurring task due on the 1st of each month.

6. **+OVERDUE:** A virtual tag that automatically gets assigned to tasks past their due date.

In addition to these attributes, Taskwarrior supports a variety of date formats and relative date expressions like `today`, `tomorrow`, `yesterday`, `now`, `sunday`, `monday`, `next week`, `last month`, etc.

---

## ToDo Support

Nvim supports following todo highlights:

- HACK
- NOTE
- PERF
- TEST
- TODO
- WARN

---
$$
