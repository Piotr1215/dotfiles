#!/usr/bin/env bash
set -eo pipefail

# Claude Configuration Cleanup Script
# Safely removes conversation history while preserving all settings

CONFIG_FILE="$HOME/.claude.json"
BACKUP_DIR="$HOME/.claude/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Get current file size
ORIGINAL_SIZE=$(du -sh "$CONFIG_FILE" | cut -f1)
print_info "Current configuration file size: $ORIGINAL_SIZE"

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/claude.json.backup-$TIMESTAMP"

print_info "Creating backup at: $BACKUP_FILE"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Compress the backup to save space
gzip "$BACKUP_FILE"
print_success "Backup created and compressed: ${BACKUP_FILE}.gz"

# Analyze current state
print_info "Analyzing conversation history..."
TOTAL_PROJECTS=$(jq '.projects | length' "$CONFIG_FILE")
TOTAL_HISTORY_ENTRIES=$(jq '[.projects[].history | length] | add' "$CONFIG_FILE")
TOTAL_HISTORY_SIZE=$(jq '.projects | to_entries | map(.value.history | tostring | length) | add' "$CONFIG_FILE")
TOTAL_HISTORY_SIZE_MB=$((TOTAL_HISTORY_SIZE / 1024 / 1024))

print_info "Found $TOTAL_PROJECTS projects with $TOTAL_HISTORY_ENTRIES total history entries (~${TOTAL_HISTORY_SIZE_MB}MB)"

# Option to keep recent history
KEEP_RECENT=""
if [[ "${1:-}" == "--keep-recent" ]]; then
    KEEP_RECENT="${2:-10}"
    print_info "Will keep the $KEEP_RECENT most recent history entries per project"
fi

# Clean up history
print_info "Cleaning conversation history..."

if [[ -n "$KEEP_RECENT" ]]; then
    # Keep only the most recent N entries per project
    jq --argjson keep "$KEEP_RECENT" '
        .projects |= with_entries(
            .value.history = (.value.history // [] | .[-$keep:])
        )
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
else
    # Remove all history entries
    jq '
        .projects |= with_entries(
            .value.history = []
        )
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
fi

# Verify the cleaned file is valid JSON
if ! jq empty "${CONFIG_FILE}.tmp" 2>/dev/null; then
    print_error "Failed to create valid JSON. Aborting cleanup."
    rm -f "${CONFIG_FILE}.tmp"
    exit 1
fi

# Replace original with cleaned version
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

# Report results
NEW_SIZE=$(du -sh "$CONFIG_FILE" | cut -f1)
NEW_HISTORY_ENTRIES=$(jq '[.projects[].history | length] | add' "$CONFIG_FILE")
NEW_HISTORY_ENTRIES=${NEW_HISTORY_ENTRIES:-0}

print_success "Cleanup complete!"
print_info "Original size: $ORIGINAL_SIZE"
print_info "New size: $NEW_SIZE"
print_info "Remaining history entries: $NEW_HISTORY_ENTRIES"
print_info "Backup saved at: ${BACKUP_FILE}.gz"

# Option to list projects with settings preserved
if [[ "${1:-}" == "--verbose" ]] || [[ "${3:-}" == "--verbose" ]]; then
    print_info "Projects with preserved settings:"
    jq -r '.projects | keys | .[]' "$CONFIG_FILE" | head -20
    REMAINING=$(jq '.projects | keys | length' "$CONFIG_FILE")
    if [[ $REMAINING -gt 20 ]]; then
        print_info "... and $((REMAINING - 20)) more projects"
    fi
fi

# Remind about other cleanup options
print_info "💡 Tip: You can also clean up old projects with:"
print_info "   jq 'del(.projects[\"path/to/old/project\"])' $CONFIG_FILE"
print_info ""
print_info "To keep recent history, run with: $0 --keep-recent 5"