### LSP

K twice enters the hover window so can copy from there etc

### Insert mode

Ctrl + y - copy character from the line above
Ctrl + e - copy character from the line below

---

### Plugins

#### Nvim Surround

    Old text                    Command         New text

---

    surr*ound_words             ysiw)           (surround_words)
    *make strings               ys$"            "make strings"
    [delete ar*ound me!]        ds]             delete around me!
    remove <b>HTML t*ags</b>    dst             remove HTML tags
    'change quot*es'            cs'"            "change quotes"
    <b>or tag* types</b>        csth1<CR>       <h1>or tag types</h1>
    delete(functi*on calls)     dsf             function calls

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
