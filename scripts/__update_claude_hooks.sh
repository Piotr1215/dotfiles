#!/usr/bin/env bash
# Update Claude settings.json with all necessary hooks
set -eo pipefail

SETTINGS_FILE="/home/decoder/.claude/settings.json"
SETTINGS_DIR="/home/decoder/.claude"

# Create settings directory if it doesn't exist
mkdir -p "$SETTINGS_DIR"

# Create or update settings.json with all hooks
cat > "$SETTINGS_FILE" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(grep*:*)",
      "Bash(exa:*,ls:*,find:*,fd,rg:*,rga,tail:*,xargs:*,head)",
      "Bash(gh view,gh pr view,gh issue view,gh pr diff,git log)",
      "WebFetch(*:*,*/*)",
      "Fetch(*)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__agentic-framework__register-agent",
        "hooks": [
          {
            "type": "command",
            "command": "/home/decoder/dev/dotfiles/scripts/__mcp_agent_registration_hook.sh"
          }
        ]
      },
      {
        "matcher": "mcp__agentic-framework__unregister-agent",
        "hooks": [
          {
            "type": "command",
            "command": "/home/decoder/dev/dotfiles/scripts/__mcp_agent_registration_hook.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/home/decoder/dev/dotfiles/scripts/__claude_notification_hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/home/decoder/dev/dotfiles/scripts/__claude_stop_hook.sh"
          }
        ]
      }
    ]
  }
}
EOF

echo "✅ Claude hooks configuration updated in $SETTINGS_FILE"
echo ""
echo "🪝 Configured hooks:"
echo "  • PostToolUse: Agent registration/unregistration"
echo "  • Notification: Claude notification handling"
echo "  • Stop: Claude output completion detection (replaces tmux pipe-pane)"
echo ""
echo "📝 Hook scripts:"
echo "  • __mcp_agent_registration_hook.sh"
echo "  • __claude_notification_hook.sh"
echo "  • __claude_stop_hook.sh"
echo ""
echo "🚀 The tmux pipe-pane monitoring has been completely replaced!"
echo "   All functionality is handled through Claude's native hook system."
echo "   The Stop hook detects when Claude finishes processing and creates notifications."