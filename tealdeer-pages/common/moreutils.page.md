# moreutils

> Additional Unix utilities

- Run command only on failure output:

`chronic <command>`

- Combine files with boolean ops:

`combine <file1> <op> <file2>`

- Look up error codes:

`errno <code>`

- Get network interface info:

`ifdata -p <interface>`

- Run if input not empty:

`ifne <command>`

- Execute with lock held:

`lckdo <lockfile> <command>`

- Pipe preserving first exit code:

`mispipe <cmd1> <cmd2>`

- Run parallel jobs:

`parallel <command>`

- Tee to multiple commands:

`pee <cmd1> <cmd2>`

- Buffer output then write:

`<command> | sponge <file>`

- Timestamp input lines:

`<command> | ts`

- Edit directory as text:

`vidir <directory>`

- Edit in pipeline:

`<command> | vipe | <command>`

- Auto-uncompress arguments:

`zrun <command> <compressed-file>`

