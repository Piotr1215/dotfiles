#!/usr/bin/env python3

import json
import sys

def main():
    try:
        # Read the 'before' and 'after' task JSON from stdin
        before = json.loads(sys.stdin.readline())
        after = json.loads(sys.stdin.readline())
        
        before_tags = set(before.get('tags', []))
        after_tags = set(after.get('tags', []))
        
        # Handle review tag (priority -1)
        if 'review' in after_tags and 'review' not in before_tags:
            after['manual_priority'] = "-1.000000"
        elif 'review' in before_tags and 'review' not in after_tags:
            # Only remove if 'next' is not present
            if 'next' not in after_tags:
                after.pop('manual_priority', None)
                
        # Handle next tag (priority 1)
        if 'next' in after_tags and 'next' not in before_tags:
            after['manual_priority'] = "1.000000"
        elif 'next' in before_tags and 'next' not in after_tags:
            # Only remove if 'review' is not present
            if 'review' not in after_tags:
                after.pop('manual_priority', None)
        
        print(json.dumps(after))
        sys.exit(0)
        
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
