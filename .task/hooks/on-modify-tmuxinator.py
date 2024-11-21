#!/usr/bin/env python3
import sys
import json
import subprocess

def main():
    try:
        # Read the 'before' and 'after' task JSON from stdin
        before_json = sys.stdin.readline()
        after_json = sys.stdin.readline()

        # Parse JSON data
        before = json.loads(before_json)
        after = json.loads(after_json)

        # Determine if the 'start' attribute exists in before and after
        before_has_start = 'start' in before
        after_has_start = 'start' in after

        # Retrieve the 'session' UDA (case-sensitive)
        session = after.get('session', '').strip()

        # If 'session' is specified, manage tmuxinator sessions
        if session:
            session_name = session
            
            # Handle session start
            if not before_has_start and after_has_start:
                subprocess.Popen(['tmuxinator', 'start', session_name])
                print(f"Started tmuxinator session: {session_name}")
            
            # Handle session stop
            elif before_has_start and not after_has_start:
                subprocess.Popen(['tmuxinator', 'stop', session_name])
                print(f"Stopped tmuxinator session: {session_name}")

        # Output the modified task
        print(json.dumps(after))
        sys.exit(0)

    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
