#!/usr/bin/env python3
import json, os, sys
before = json.loads(input())
after = json.loads(input())
if 'piotr' in after.get('tags', []):
    action = None
    if 'start' not in before and 'start' in after:
        action = 'start'
    elif 'start' in before and 'start' not in after and not os.getenv('HANDOFF_SWITCH'):
        action = 'stop'
    if 'start' in before and 'start' not in after:
        with open(os.environ['HANDOFF_STOP_LOG'], 'a') as log:
            log.write(f"{after['uuid']} {os.getenv('HANDOFF_SWITCH', '')}\n")
    if action:
        with open(os.environ['HANDOFF_NAV_LOG'], 'a') as log:
            log.write(f"{action} {after['uuid']}\n")
print(json.dumps(after))
