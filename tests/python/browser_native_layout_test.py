#!/usr/bin/env python3
"""The host runs a shell script for the browser, so the layout argument is a
trust boundary: only known layout numbers may through. Run: python3 <this>"""
import json
import struct
import subprocess

HOST = "scripts/__browser_native_layout.py"


def ask(payload):
    body = json.dumps(payload).encode()
    r = subprocess.run(
        [HOST], input=struct.pack("<I", len(body)) + body, capture_output=True
    )
    assert r.stdout[:4], "host wrote no response: " + r.stderr.decode()[-300:]
    return json.loads(r.stdout[4:].decode())


for bad in [{"layout": "9"}, {"layout": "5; touch /tmp/pwned"}, {"layout": "../x"}, {}]:
    got = ask(bad)
    assert got["ok"] is False, (bad, got)
    print("rejected:", bad, "->", got["error"])

print("all rejections held")
