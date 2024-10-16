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
            if not before_has_start and after_has_start:
                # Task was started: start the tmuxinator session
                subprocess.Popen(['tmuxinator', 'start', session_name])
            # Removed the condition to stop the session when the task is stopped

        # Output the 'after' task JSON unmodified
        print(json.dumps(after))

    except Exception as e:
        # If an error occurs, exit with a non-zero status
        sys.exit(1)

if __name__ == '__main__':
    main()
