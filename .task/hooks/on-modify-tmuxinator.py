#!/usr/bin/env python3

import sys
import json
import subprocess

def main():
    # Read the 'before' and 'after' task from stdin
    before_json = sys.stdin.readline()
    after_json = sys.stdin.readline()

    # Parse JSON
    before = json.loads(before_json)
    after = json.loads(after_json)

    # Check the 'start' attribute
    before_has_start = 'start' in before
    after_has_start = 'start' in after

    # Get the task description
    description = after.get('description', '').lower()

    # Check if the description matches 'fill standup forms'
    if 'fill standup forms' in description:
        if not before_has_start and after_has_start:
            # Task was started
            subprocess.Popen(['tmuxinator', 'start', 'standup'])
        elif before_has_start and not after_has_start:
            # Task was stopped
            subprocess.Popen(['tmuxinator', 'stop', 'standup'])

    # Output the 'after' task unmodified
    print(json.dumps(after))

if __name__ == '__main__':
    main()
