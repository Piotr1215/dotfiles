#!/usr/bin/env python3

# PROJECT: ai
# Claude Status Monitor for Argos
# Shows green/red indicator based on Claude notification files

import os
import glob
from datetime import datetime

def get_notification_files():
    """Get all Claude notification files"""
    pattern = "/run/user/1000/claude-monitor/claude-notification-*"
    return glob.glob(pattern)

def get_notification_count():
    """Count pending Claude notifications"""
    files = get_notification_files()
    return len([f for f in files if os.path.isfile(f)])

def get_sessions_info():
    """Get information about pending Claude sessions"""
    files = get_notification_files()
    sessions = []
    
    for file_path in files:
        if os.path.isfile(file_path):
            try:
                # Extract session info from filename: claude-notification-SESSION-WINDOW-PANE-TIMESTAMP
                filename = os.path.basename(file_path)
                
                # Parse filename from right to left to handle hyphens in session names
                if filename.startswith("claude-notification-"):
                    remainder = filename[len("claude-notification-"):]
                    
                    # Split from the end: timestamp, pane, window, then session gets the rest
                    parts = remainder.rsplit('-', 3)
                    if len(parts) == 4:
                        session = parts[0]
                        window = parts[1]
                        pane = parts[2]
                        timestamp = parts[3]
                        
                        # Read title from file content
                        with open(file_path, 'r') as f:
                            content = f.read().strip()
                            title = content.split(':')[-1] if ':' in content else "Claude notification"
                        
                        sessions.append({
                            'session': session,
                            'window': window,
                            'pane': pane,
                            'timestamp': timestamp,
                            'title': title,
                            'file': file_path
                        })
            except Exception:
                continue
    
    # Sort by timestamp (oldest first)
    sessions.sort(key=lambda x: int(x['timestamp']) if x['timestamp'].isdigit() else 0)
    return sessions

def main():
    """Main function to generate Argos output"""
    count = get_notification_count()
    
    # Menu bar icon with AI symbol
    if count > 0:
        # Red icon with AI symbol on right for pending notifications
        if count == 1:
            print("🔴🧠")
        else:
            print(f"🔴{count}🧠")
    else:
        # Green icon with AI symbol on right when all caught up
        print("🟢🧠")
    
    print("---")
    
    # Dropdown content
    if count > 0:
        print(f"Claude Notifications ({count}) | size=14")
        print("---")
        
        sessions = get_sessions_info()
        for i, session_info in enumerate(sessions, 1):
            session_name = session_info['session']
            window = session_info['window']
            title = session_info['title']
            
            # Show session info
            print(f"{i}. {session_name}:{window} | size=12")
            print(f"   {title} | size=10 color=#666666")
        
        print("---")
        print("Use keybinding to cycle through sessions | size=10 color=#888888")
    else:
        print("All Claude sessions up to date | size=14 color=#2ecc71")
    
    # Footer
    print("---")
    print(f"Last checked: {datetime.now().strftime('%H:%M:%S')} | size=9 color=#999999")

if __name__ == "__main__":
    main()
