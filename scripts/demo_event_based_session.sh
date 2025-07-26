#!/usr/bin/env bash

echo "🎬 Event-Based Session Demo"
echo "=========================="
echo ""

case "${1:-}" in
    "degrade")
        echo "🚨 Simulating service degradation..."
        echo ""
        
        # Create degraded state
        cat > ~/.local/state/argos-service-monitor/services_status_state.json << EOF
{
  "statuses": {
    "GitHub": "major",
    "AWS": "degraded",
    "GCP": "operational",
    "Azure": "operational",
    "Netlify": "operational",
    "Linear": "operational",
    "GoDaddy": "operational",
    "Claude": "operational",
    "Quay": "operational"
  },
  "degradation_counts": {
    "GitHub": 2,
    "AWS": 2
  },
  "notification_cooldowns": {},
  "last_updated": "$(date -Iseconds)"
}
EOF
        
        echo "📝 Created degradation state:"
        echo "   - GitHub: major outage"
        echo "   - AWS: degraded performance"
        echo ""
        echo "⏱️  Triggering monitor script immediately..."
        /home/decoder/dev/dotfiles/scripts/__service_monitor_cron.sh
        
        echo "🔄 Updating Argos display..."
        # Trigger Argos to refresh by touching the script
        touch /home/decoder/dev/dotfiles/scripts/services-status.5m.py
        
        echo ""
        echo "✅ Session should now be created!"
        echo "🔴 Status bar should show degraded services!"
        echo ""
        echo "💡 Next: Run './scripts/demo_event_based_session.sh recover' to simulate recovery"
        ;;
        
    "recover")
        echo "✅ Simulating service recovery..."
        echo ""
        
        # Create all operational state
        cat > ~/.local/state/argos-service-monitor/services_status_state.json << EOF
{
  "statuses": {
    "AWS": "operational",
    "GCP": "operational",
    "Azure": "operational",
    "Netlify": "operational",
    "GitHub": "operational",
    "Linear": "operational",
    "GoDaddy": "operational",
    "Claude": "operational",
    "Quay": "operational"
  },
  "degradation_counts": {},
  "notification_cooldowns": {},
  "last_updated": "$(date -Iseconds)"
}
EOF
        
        echo "🟢 All services now operational"
        echo ""
        echo "⏱️  Triggering monitor script immediately..."
        /home/decoder/dev/dotfiles/scripts/__service_monitor_cron.sh
        
        echo "🔄 Updating Argos display..."
        # Trigger Argos to refresh by touching the script
        touch /home/decoder/dev/dotfiles/scripts/services-status.5m.py
        
        echo ""
        echo "✅ Session should now be killed!"
        echo "🟢 Status bar should show all services operational!"
        ;;
        
    "status")
        echo "📊 Current Status:"
        echo ""
        
        # Check session
        if tmux has-session -t servmon 2>/dev/null; then
            echo "✅ servmon session is RUNNING"
            tmux list-windows -t servmon
        else
            echo "❌ servmon session is NOT running"
        fi
        
        echo ""
        echo "📄 Service states:"
        jq -r '.statuses | to_entries | .[] | "   \(.key): \(.value)"' ~/.local/state/argos-service-monitor/services_status_state.json
        
        echo ""
        echo "📝 Recent monitor activity:"
        tail -5 ~/.local/state/argos-service-monitor/monitor.log
        ;;
        
    *)
        echo "Usage: $0 [degrade|recover|status]"
        echo ""
        echo "Commands:"
        echo "  degrade  - Simulate service degradation (triggers session creation)"
        echo "  recover  - Simulate service recovery (triggers session destruction)"
        echo "  status   - Show current status and session info"
        echo ""
        echo "For video demo:"
        echo "1. Run '$0 degrade' to trigger degradation"
        echo "2. Wait ~60 seconds for cron to create session"
        echo "3. Show the servmon session with M-t"
        echo "4. Run '$0 recover' to trigger recovery"
        echo "5. Wait ~60 seconds for cron to kill session"
        ;;
esac