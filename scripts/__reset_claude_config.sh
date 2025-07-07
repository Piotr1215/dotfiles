#!/usr/bin/env bash
set -eo pipefail

# MCP-centric Claude config reset
# Replaces MCP servers with template versions
# Preserves all other settings except projects array

TARGET="/home/decoder/.claude.json"
TEMPLATE="/home/decoder/.claude.json.template"

echo "=== Claude MCP Config Reset ==="
echo ""

# Backup current to /tmp (auto-cleaned on restart)
BACKUP_FILE="/tmp/claude.json.backup.$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP_FILE" && echo "📁 Backed up to: $BACKUP_FILE"

# Check if template exists
if [[ ! -f "$TEMPLATE" ]]; then
    echo "❌ CRITICAL: Template file not found: $TEMPLATE"
    echo "Cannot update MCP servers - manual intervention required!"
    exit 1
fi

echo "🔄 Updating MCP servers from template..."
echo "🙌 Preserving all other settings..."
echo "🧹 Clearing projects section..."

# Get MCP servers from template
TEMPLATE_MCP_SERVERS=$(jq '.mcpServers' "$TEMPLATE")

# Update the target file:
# 1. Replace mcpServers with template version
# 2. Delete projects array
# 3. Keep everything else as-is
if command -v sponge >/dev/null 2>&1; then
    jq --argjson mcp "$TEMPLATE_MCP_SERVERS" '.mcpServers = $mcp | del(.projects)' "$TARGET" | sponge "$TARGET"
else
    jq --argjson mcp "$TEMPLATE_MCP_SERVERS" '.mcpServers = $mcp | del(.projects)' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
fi

echo "✅ MCP servers updated from template!"

# Hooks are now managed in settings.json, not .claude.json

echo ""
echo "📊 MCP Server Status:"
echo "━━━━━━━━━━━━━━━━━━━"

echo "  🔄 Updated from template:"

# List MCP servers
jq -r '.mcpServers | to_entries[] | "  • \(.key)"' "$TARGET" 2>/dev/null || echo "  ❌ No servers found"

echo ""
echo "🔐 Config Summary:"
echo "━━━━━━━━━━━━━━━━━"
echo "  MCP Servers: $(jq '.mcpServers | length // 0' "$TARGET")"
echo "  UserID: $(jq -r '.userID' "$TARGET" | cut -c1-10)..."
echo "  OAuth: $(jq -r '.oauthAccount.emailAddress // "not configured"' "$TARGET")"
echo "  Projects: $(jq '.projects | length // 0' "$TARGET") (should be 0)"
echo ""
echo "💡 Template: $TEMPLATE"
echo "   Edit this template to change MCP server configurations"
echo ""
echo "✨ MCP servers updated successfully!"