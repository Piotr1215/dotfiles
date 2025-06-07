#!/usr/bin/env bash
set -eo pipefail

# Restore latest Claude configuration from restic backup

TARGET_FILE="/home/decoder/.claude.json"
BACKUP_FILE="${TARGET_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
SECURE_STORE="/mnt/nas-backup/secure-store"

# Setup display for notifications
display_num=$(find /tmp/.X11-unix/ -type s -name "X*" | head -n 1 | sed 's#/tmp/.X11-unix/X##')
export DISPLAY=":${display_num}"
user_id=$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus"

# Send notification
notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    local icon="$4"
    
    dunstify \
        --timeout 10000 \
        --urgency="$urgency" \
        --icon="$icon" \
        "$title" \
        "$message" 2>/dev/null
}

# Check if NAS is mounted
if ! mountpoint -q /mnt/nas-backup; then
    echo "Error: NAS is not mounted. Cannot access restic repository."
    notify "critical" "Restore Failed" "NAS is not mounted" "dialog-error"
    exit 1
fi

# Set restic repository
export RESTIC_REPOSITORY="$SECURE_STORE"

echo "Checking for Claude config backups in restic repository..."

# Find snapshots containing the target file
snapshots=$(restic snapshots --json | jq -r '.[] | select(.paths[] | contains("'$TARGET_FILE'")) | .id' 2>/dev/null)

if [ -z "$snapshots" ]; then
    echo "No backups found for $TARGET_FILE"
    notify "critical" "Restore Failed" "No backups found for Claude config" "dialog-error"
    exit 1
fi

# Get the latest snapshot
latest_snapshot=$(echo "$snapshots" | head -n 1)
snapshot_date=$(restic snapshots --json | jq -r '.[] | select(.id == "'$latest_snapshot'") | .time' 2>/dev/null)

echo "Latest backup found:"
echo "  Snapshot ID: $latest_snapshot"
echo "  Date: $snapshot_date"
echo "  Target file: $TARGET_FILE"

# Backup current file if it exists
if [ -f "$TARGET_FILE" ]; then
    echo "Creating backup of current file: $BACKUP_FILE"
    cp "$TARGET_FILE" "$BACKUP_FILE"
fi

# Create temporary directory for restoration
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

echo "Restoring from snapshot $latest_snapshot..."

# Restore the file
if restic restore "$latest_snapshot" --target "$temp_dir" --include "$TARGET_FILE"; then
    # Move the restored file to the correct location
    restored_file="${temp_dir}${TARGET_FILE}"
    
    if [ -f "$restored_file" ]; then
        mv "$restored_file" "$TARGET_FILE"
        echo "Successfully restored $TARGET_FILE from backup dated $snapshot_date"
        
        # Show file info
        echo "Restored file details:"
        ls -la "$TARGET_FILE"
        
        notify "normal" "Claude Config Restored" "Successfully restored from backup\nDate: $(date -d "$snapshot_date" '+%Y-%m-%d %H:%M')" "applications-chat"
    else
        echo "Error: Restored file not found at expected location"
        notify "critical" "Restore Failed" "Restored file not found" "dialog-error"
        exit 1
    fi
else
    echo "Error: Failed to restore from restic backup"
    notify "critical" "Restore Failed" "Restic restore operation failed" "dialog-error"
    exit 1
fi

echo "Restore completed successfully!"

# Optionally show the differences if a backup was created
if [ -f "$BACKUP_FILE" ]; then
    echo ""
    echo "To see differences between old and restored config:"
    echo "  diff '$BACKUP_FILE' '$TARGET_FILE'"
    echo ""
    echo "To restore the previous version:"
    echo "  mv '$BACKUP_FILE' '$TARGET_FILE'"
fi