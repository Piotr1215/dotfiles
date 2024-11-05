#!/usr/bin/env python3

import sys
import json

def main():
    try:
        # Read the 'before' and 'after' task JSON from stdin
        before = json.loads(sys.stdin.readline())
        after = json.loads(sys.stdin.readline())
        
        # Check if the task is being completed
        if after.get('status') == 'completed' and before.get('status') != 'completed':
            # Get current tags, defaulting to empty list if none exist
            tags = set(after.get('tags', []))
            
            # Remove specific tags if they exist
            tags.discard('started')
            tags.discard('review')
            
            # Update the task's tags
            after['tags'] = list(tags)
            
            # Optional: provide feedback if tags were removed
            if 'started' in before.get('tags', []) or 'review' in before.get('tags', []): 
                print("Removed 'started' and 'review' tags from completed task")
        
        # Output the modified task
        print(json.dumps(after))
        sys.exit(0)
        
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
