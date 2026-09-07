# Development Guidelines for Dotfiles Repository

## Critical Workflow Rules

### ALWAYS Read Documentation Before Implementation
- **BEFORE** attempting any solution, read relevant man pages and documentation
- **BEFORE** writing code, understand the tools and their options
- Example: For tmux scripting, read `man tmux` sections on `send-keys`, `display-message`, `split-window`
- Never guess at tool behavior - verify in documentation first

### ALWAYS Test Changes Before Presenting
- Create test cases to verify script behavior before asking user to test
- Use temporary test sessions/environments to validate changes
- Example: `tmux new-session -d -s test_session` to test tmux commands
- Never rely on user to be the first tester

### Simplicity First
- Always start with the simplest solution
- Avoid overengineering (temp files, sed injection, complex pipelines)
- Ask clarifying questions when requirements are unclear
- Example: "clear screen + display output" is simpler than "create temp file + sed replacements"

### Output Cleanliness
- Only produce output explicitly requested by user
- Suppress verbose command echoes and unnecessary information
- Use `command` to bypass aliases when needed (e.g., `command cat` bypasses `alias cat=bat`)
- Redirect noise to `/dev/null` when appropriate

### Tmux Scripting Best Practices
- Use `tmux send-keys -t pane "command"` for commands that should execute
- Omit `C-m` (Enter) when you want to type but not execute (e.g., `print -z`)
- Use `clear &&` to clean output before displaying results
- Be aware of shell aliases in tmux panes (use `command` prefix to bypass)

## Project Commands
- Install: `cd dotfiles/install && ./install.sh`
- Lint scripts: `shellcheck scripts/__*.sh`
- Run all shell tests: `cd tests/shell && bash detect_os_test.sh && bash lib_taskwarrior_interop_test.sh`
- Run single shell test: `bash tests/shell/lib_taskwarrior_interop_test.sh test_function_name`
- Run bats tests: `cd tests/bats && bats github_issue_sync_test.bats`
- Run specific bats test: `cd tests/bats && bats github_issue_sync_test.bats --filter "test_name"`
- Run python tests: `cd tests/python && python -m pytest test_*.py -v`
- Create symlinks: `stow --target=/home/[USER]/.config/[TARGET] [SOURCE]`
- Add to dotfiles: `./scripts/__dotfiles_adder.sh [PATH_TO_FILE]`

## Git Commit Guidelines
- Commit message format: `<component>: <short description>` 
- Examples: `scripts: update project mappings`, `nvim: fix plugin config`

## Code Style Guidelines
- Scripts: Use `#!/usr/bin/env bash` with `set -eo pipefail`
- Naming: 
  - Scripts: Double underscore prefix (`__script_name.sh`)
  - Functions: Snake_case (`function_name()`)
  - Library scripts: `__lib_` prefix
  - Variables: Lowercase snake_case with `local` keyword
- Documentation: Comment above each function explaining purpose
- Error handling: Use `>&2` for error messages, proper exit codes (exit 1)
- Tests:
  - Legacy tests: `_tests.sh` suffix with assertion and cleanup functions
  - Bats tests: `_tests.bats` suffix with `@test` annotations
  - See `scripts/README_TESTS.md` for detailed testing guidelines

## Common Patterns
- Source other scripts with `source ./__script_name.sh`
- Debug traces with `export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'`
- IFS setting with `$'\n\t'` for safer word splitting
- Modular functions with single responsibilities
- Defensive coding with parameter validation
- when creating scripts never create v2 etc but modify existing ones

## Debugging Window Management
- For troubleshooting window management scripts (`__layouts.sh`):
  - Add timestamp debugging (`echo "$(date +%T.%N): Action description"`) to identify where delays occur
  - Avoid `--sync` flags with `xdotool windowsize/windowmove` operations, as they can cause significant delays (15+ seconds)
  - For Firefox/Slack layouts, always activate Firefox first to ensure it's on the current workspace
  - Use `set -x` to trace execution when debugging window management issues
  - Firefox may appear full-screen if resize operations are applied before unmaximizing
  - Use timeout commands (e.g., `timeout 5 xdotool command`) to prevent hanging on problematic operations

## File Organization
- Utility scripts in `/scripts/`
- Installation files in `/install/`
- Configuration templates by tool
- Test scripts alongside implementation files

## Tool Recommendations
- Use `fd` instead of `find`