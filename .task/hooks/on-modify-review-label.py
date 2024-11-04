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
        
        # Add manual_priority when review tag is added
        if 'review' in after_tags and 'review' not in before_tags:
            after['manual_priority'] = "-1.000000"
            
        # Remove manual_priority when review tag is removed
        if 'review' in before_tags and 'review' not in after_tags:
            after.pop('manual_priority', None)
        
        print(json.dumps(after))
        
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
