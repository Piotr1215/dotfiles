#!/usr/bin/env python3
import sys
import json
import subprocess

def should_close_session(task):
    tags = set(task.get('tags', []))
    return 'kill' in tags

def main():
    try:
        before = json.loads(sys.stdin.readline())
        after = json.loads(sys.stdin.readline())

        before_has_start = 'start' in before
        after_has_start = 'start' in after
        session = after.get('session', '').strip()

        if session:
            if not before_has_start and after_has_start:
                subprocess.Popen(['tmuxinator', 'start', session])
                print(f"Started tmuxinator session: {session}")
            elif before_has_start and not after_has_start and should_close_session(after):
                subprocess.Popen(['tmuxinator', 'stop', session])
                print(f"Stopped tmuxinator session: {session}")

        print(json.dumps(after))
        sys.exit(0)

    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
