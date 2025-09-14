#!/usr/bin/env python3
"""
Claude Code Hook: Bash Command Validator
=========================================
This hook runs as a PreToolUse hook for the Bash tool.
It validates bash commands against a set of rules before execution.
Encourages better tool choices (rg over grep, fd over find, etc.)

To enable, add to ~/.claude/settings.json:
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /home/decoder/dev/dotfiles/scripts/__bash_command_validator.py"
          }
        ]
      }
    ]
  }
}
"""

import json
import re
import sys
from typing import List, Tuple

# Define validation rules as a list of (regex pattern, message) tuples
# Easy to add new rules - just append to this list!
_VALIDATION_RULES: List[Tuple[str, str]] = [
    # File searching improvements
    (
        r"^grep\b(?!.*\|)",
        "Use 'rg' (ripgrep) instead of 'grep' for better performance and features",
    ),
    (
        r"\bgrep -r\b",
        "Use 'rg' instead of 'grep -r' for recursive search (much faster)",
    ),
    (
        r"^find\s+.*-name\b",
        "Use 'fd pattern' instead of 'find -name' for better performance and simpler syntax",
    ),
    (
        r"^find\s+.*-type\s+f",
        "Use 'fd --type f pattern' instead of 'find -type f' for finding files",
    ),
    (
        r"^find\s+.*-type\s+d",
        "Use 'fd --type d pattern' instead of 'find -type d' for finding directories",
    ),
    (
        r"^find\s+\.",
        "Use 'fd' instead of 'find .' for better performance and cleaner output",
    ),

    # Cat improvements for syntax highlighting
    (
        r"^cat\s+.*\.(py|js|ts|lua|rs|go|cpp|c|java|rb|sh|bash|zsh|fish|vim|yaml|yml|json|toml|md|markdown)(\s|$)",
        "Consider 'bat' instead of 'cat' for syntax highlighting (if available)",
    ),

    # Process management
    (
        r"^ps aux.*grep",
        "Use 'pgrep' or 'pidof' for finding processes by name",
    ),
    (
        r"^kill -9\b",
        "Try 'kill' (SIGTERM) first before 'kill -9' (SIGKILL) to allow graceful shutdown",
    ),

    # Archive handling
    (
        r"^tar -?[cxz].*f\s+",
        "Consider using 'atool' for unified archive handling (works with tar, zip, rar, etc.)",
    ),

    # Network tools
    (
        r"^curl\s+-X\s+POST.*-H.*application/json",
        "Consider using 'httpie' (http) for more readable JSON API interactions",
    ),

    # Disk usage
    (
        r"^du -sh\b",
        "Consider 'dust' or 'duf' for better disk usage visualization",
    ),
    (
        r"^df -h\b",
        "Consider 'duf' for better disk free space visualization",
    ),

    # Common inefficiencies
    (
        r"cat.*\|.*grep",
        "Use 'rg pattern file' directly instead of 'cat file | grep pattern'",
    ),
    (
        r"grep.*\|.*wc -l",
        "Use 'rg -c pattern' instead of 'grep pattern | wc -l' to count matches",
    ),
    (
        r"find.*-exec.*rm",
        "Use 'fd pattern --exec rm {}' or 'fd pattern -X rm' for safer deletion",
    ),
]

# Suggestions for tool installation (shown only once per session)
_TOOL_SUGGESTIONS = {
    "rg": "Install with: cargo install ripgrep OR apt install ripgrep",
    "fd": "Install with: cargo install fd-find OR apt install fd-find",
    "bat": "Install with: cargo install bat OR apt install bat",
    "dust": "Install with: cargo install du-dust",
    "duf": "Install with: go install github.com/muesli/duf@latest OR apt install duf",
    "httpie": "Install with: pip install httpie OR apt install httpie",
    "jq": "Install with: apt install jq",
    "atool": "Install with: apt install atool",
    "pgrep": "Usually pre-installed (part of procps)",
}


def _validate_command(command: str) -> List[str]:
    """Check command against all validation rules."""
    issues = []
    for pattern, message in _VALIDATION_RULES:
        if re.search(pattern, command, re.IGNORECASE):
            issues.append(message)

            # Extract tool name from message if it suggests an alternative
            if "Use '" in message or "Consider '" in message:
                # Extract tool name (first word after "Use '" or "Consider '")
                tool_match = re.search(r"(?:Use|Consider)\s+'(\w+)", message)
                if tool_match:
                    tool = tool_match.group(1)
                    if tool in _TOOL_SUGGESTIONS:
                        issues.append(f"  → {_TOOL_SUGGESTIONS[tool]}")

    return issues


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        # Exit code 1 shows stderr to the user but not to Claude
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    if not command:
        sys.exit(0)

    # Special case: allow certain patterns that would normally be blocked
    # For example, if explicitly checking if a tool exists
    allow_patterns = [
        r"^which\s+(grep|find|ls|cat|ps|tar|curl|du|df)\b",
        r"^command\s+-v\s+(grep|find|ls|cat|ps|tar|curl|du|df)\b",
        r"^type\s+(grep|find|ls|cat|ps|tar|curl|du|df)\b",
    ]

    for pattern in allow_patterns:
        if re.search(pattern, command):
            sys.exit(0)  # Allow these commands

    issues = _validate_command(command)
    if issues:
        print("Command improvement suggestions:", file=sys.stderr)
        for message in issues:
            print(f"• {message}", file=sys.stderr)

        # Exit code 2 blocks tool call and shows stderr to Claude
        # This encourages Claude to use better tools
        sys.exit(2)


if __name__ == "__main__":
    main()
