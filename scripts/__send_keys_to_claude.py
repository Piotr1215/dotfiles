#!/usr/bin/env python3
"""Send keys to registered Claude tmux sessions using libtmux."""

import sys
import json
import glob
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    import libtmux
except ImportError:
    print("Error: libtmux not installed. Install with: pip install libtmux")
    sys.exit(1)


def get_current_tmux_context():
    """Get current tmux session, window, and pane info."""
    try:
        import os
        
        # Check if we're in a tmux session
        tmux_session = os.environ.get('TMUX')
        if not tmux_session:
            return None
            
        server = libtmux.Server()
        
        # Get current session
        current_session = server.attached_session
        if not current_session:
            return None
            
        # Get current window
        current_window = current_session.attached_window
        if not current_window:
            return None
            
        # Get current pane
        current_pane = current_window.attached_pane
        if not current_pane:
            return None
            
        return {
            'session': current_session.session_name,
            'window': current_window.window_index,
            'pane': current_pane.pane_index
        }
    except Exception:
        return None


def find_claude_sessions():
    """Find all registered Claude sessions from broadcast tracking files."""
    tracking_files = glob.glob("/tmp/claude_broadcast_*.json")
    sessions = []
    
    # Get current tmux context to exclude it
    current_context = get_current_tmux_context()
    
    for file_path in tracking_files:
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                
            session_info = {
                'file': file_path,
                'session': data['session'],
                'window': data['window'],
                'pane': data['pane'],
                'instance_id': data.get('instance_id', 'Unknown'),
                'pid': data.get('pid', 'Unknown'),
                'start_time': data.get('start_time', 'Unknown')
            }
            
            # Skip current session/window/pane to avoid sending to ourselves
            if current_context and (
                session_info['session'] == current_context['session'] and
                str(session_info['window']) == str(current_context['window']) and
                str(session_info['pane']) == str(current_context['pane'])
            ):
                print(f"Skipping current session: {session_info['session']}:{session_info['window']}.{session_info['pane']}")
                continue
                
            sessions.append(session_info)
        except Exception as e:
            print(f"Warning: Failed to read {file_path}: {e}")
    
    return sessions


def send_keys_to_session(session_name, window_id, pane_id, keys_to_send):
    """Send keys to a specific tmux pane."""
    try:
        server = libtmux.Server()
        
        # Find the session by name
        session = None
        for s in server.sessions:
            if s.session_name == session_name:
                session = s
                break
        
        if not session:
            print(f"Error: Session '{session_name}' not found")
            return False
        
        # Find the window by index
        window = None
        for w in session.windows:
            if w.window_index == str(window_id):
                window = w
                break
        
        if not window:
            print(f"Error: Window '{window_id}' not found in session '{session_name}'")
            return False
        
        # Find the pane by index
        pane = None
        for p in window.panes:
            if p.pane_index == str(pane_id):
                pane = p
                break
        
        if not pane:
            print(f"Error: Pane '{pane_id}' not found in window '{window_id}'")
            return False
        
        # Send the keys
        # Don't send Enter key - let the user decide if they want to execute
        pane.send_keys(keys_to_send, enter=False)
        print(f"✓ Sent to {session_name}:{window_id}.{pane_id}")
        return True
        
    except Exception as e:
        print(f"Error sending keys: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Send keys to registered Claude tmux sessions")
    parser.add_argument("keys", nargs='?', help="Keys to send (use quotes for spaces)")
    parser.add_argument("-l", "--list", action="store_true", help="List all registered sessions")
    parser.add_argument("-s", "--session", help="Target specific session by name")
    parser.add_argument("-a", "--all", action="store_true", help="Send to all sessions")
    parser.add_argument("-x", "--exclude", help="Exclude session:window.pane (e.g., main:1.3)")
    
    args = parser.parse_args()
    
    # Find all Claude sessions
    sessions = find_claude_sessions()
    
    if args.list or not args.keys:
        if not sessions:
            print("No registered Claude sessions found")
        else:
            print("Registered Claude sessions:")
            for i, sess in enumerate(sessions):
                print(f"  {i+1}. {sess['session']}:{sess['window']}.{sess['pane']} (PID: {sess['pid']})")
        
        if not args.keys and not args.list:
            print("\nUsage: Provide text to send, e.g.:")
            print(f"  {sys.argv[0]} 'Hello Claude!'")
            print(f"  {sys.argv[0]} -s session_name 'Hello Claude!'")
            print(f"  {sys.argv[0]} -a 'Broadcast message'")
        return
    
    if not sessions:
        print("No registered Claude sessions found")
        return
    
    # Send to specific session
    if args.session:
        target_sessions = [s for s in sessions if s['session'] == args.session]
        if not target_sessions:
            print(f"Error: Session '{args.session}' not found")
            return
    # Send to all sessions (default behavior)
    else:
        target_sessions = sessions
    
    # Send keys to selected sessions in parallel
    success_count = 0
    
    if len(target_sessions) == 1:
        # Single session - no need for threading
        if send_keys_to_session(target_sessions[0]['session'], target_sessions[0]['window'], target_sessions[0]['pane'], args.keys):
            success_count = 1
    else:
        # Multiple sessions - use parallel execution
        with ThreadPoolExecutor(max_workers=min(len(target_sessions), 10)) as executor:
            # Submit all tasks
            future_to_session = {
                executor.submit(send_keys_to_session, sess['session'], sess['window'], sess['pane'], args.keys): sess
                for sess in target_sessions
            }
            
            # Wait for completion
            for future in as_completed(future_to_session):
                if future.result():
                    success_count += 1
    
    if len(target_sessions) > 1:
        print(f"\nBroadcast to {success_count}/{len(target_sessions)} session(s)")
    elif success_count == 0:
        print("\nFailed to send message")


if __name__ == "__main__":
    main()