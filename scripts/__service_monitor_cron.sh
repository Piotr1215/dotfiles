#!/usr/bin/env bash

# Service Monitor Cron Script
# Checks service status and manages servmon session

STATE_FILE="$HOME/.local/state/argos-service-monitor/services_status_state.json"
LOG_FILE="$HOME/.local/state/argos-service-monitor/monitor.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if state file exists
if [ ! -f "$STATE_FILE" ]; then
    log_message "State file not found: $STATE_FILE"
    exit 0
fi

# Read the status file and check for degraded services
DEGRADED_COUNT=$(jq -r '.statuses | to_entries | map(select(.value != "operational")) | length' "$STATE_FILE" 2>/dev/null || echo "0")

# Check if servmon session exists
SESSION_EXISTS=false
if tmux has-session -t servmon 2>/dev/null; then
    SESSION_EXISTS=true
fi

if [ "$DEGRADED_COUNT" -gt 0 ]; then
    # Services are degraded
    if [ "$SESSION_EXISTS" = false ]; then
        # Launch servmon session
        log_message "Degraded services detected ($DEGRADED_COUNT). Launching servmon session..."
        tmuxinator start servmon
        
        # Send notification
        DEGRADED_SERVICES=$(jq -r '.statuses | to_entries | map(select(.value != "operational")) | .[] | "\(.key): \(.value)"' "$STATE_FILE" | tr '\n' ', ')
        dunstify -u critical -i dialog-warning "Service Status Alert" "Service degradation detected: $DEGRADED_SERVICES"
        
        log_message "Session launched. Degraded services: $DEGRADED_SERVICES"
    else
        log_message "Degraded services still present ($DEGRADED_COUNT). Session already running."
    fi
else
    # All services operational
    if [ "$SESSION_EXISTS" = true ]; then
        # Kill servmon session
        log_message "All services operational. Killing servmon session..."
        tmux kill-session -t servmon
        
        # Send notification
        dunstify -u normal -i dialog-information "Service Status Update" "All services operational. Monitoring session closed."
        
        log_message "Session killed. All services operational."
    else
        log_message "All services operational. No session to kill."
    fi
fi