#!/usr/bin/env bash
set -eo pipefail

# MCP-centric Claude config reset
# ONLY restores MCP servers if completely missing
# NEVER touches existing MCP server configurations

TARGET="/home/decoder/.claude.json"
TEMPLATE="/home/decoder/.claude.json.template"

echo "=== Claude MCP Config Reset ==="
echo ""

# Backup current to /tmp (auto-cleaned on restart)
BACKUP_FILE="/tmp/claude.json.backup.$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP_FILE" && echo "📁 Backed up to: $BACKUP_FILE"

# Check MCP servers
MCP_COUNT=$(jq '.mcpServers | length // 0' "$TARGET")

if [[ "$MCP_COUNT" -eq 0 ]]; then
    echo "⚠️  WARNING: NO MCP SERVERS DETECTED!"
    echo ""
    
    if [[ -f "$TEMPLATE" ]]; then
        echo "🚨 This is serious - MCP servers are essential!"
        echo "🔄 Restoring MCP servers from template..."
        
        # Get current userID to preserve
        CURRENT_USER_ID=$(jq -r '.userID // ""' "$TARGET")
        
        # Restore from template but preserve current userID
        if [[ -n "$CURRENT_USER_ID" ]]; then
            jq --arg uid "$CURRENT_USER_ID" '.userID = $uid | del(.projects)' "$TEMPLATE" > "$TARGET"
        else
            jq 'del(.projects)' "$TEMPLATE" > "$TARGET"
        fi
        
        echo "✅ MCP servers restored from template!"
    else
        echo "❌ CRITICAL: Template file not found: $TEMPLATE"
        echo "Cannot restore MCP servers - manual intervention required!"
        exit 1
    fi
else
    echo "✅ MCP servers detected ($MCP_COUNT configured)"
    echo "🙌 Preserving your MCP server configurations"
    echo "🧹 Cleaning projects section only..."
    
    # Just remove projects section - DO NOT TOUCH MCP SERVERS!
    if command -v sponge >/dev/null 2>&1; then
        jq 'del(.projects)' "$TARGET" | sponge "$TARGET"
    else
        jq 'del(.projects)' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
    fi
fi

# Hooks are now managed in settings.json, not .claude.json

echo ""
echo "📊 MCP Server Status:"
echo "━━━━━━━━━━━━━━━━━━━"

# Show if servers were restored from template
if [[ "$MCP_COUNT" -eq 0 ]] && [[ -f "$TEMPLATE" ]]; then
    echo "  📥 Restored from template:"
else
    echo "  🔧 Current configuration:"
fi

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
echo "   Edit this template to change default MCP servers"
echo ""
echo "✨ MCP servers are the key to everything!"