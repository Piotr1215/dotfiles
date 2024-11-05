#!/usr/bin/env python3

import sys
import json

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

        if not before_has_start and after_has_start:
            # Task has just been started
            after_tags = set(after.get('tags', []))
            if 'started' not in after_tags:
                # Add '+started' tag if not present
                after_tags.add('started')
                after['tags'] = list(after_tags)

        # Output the modified 'after' task JSON
        print(json.dumps(after))

    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
