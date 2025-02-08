#!/usr/bin/env python3
# -*- coding: utf-8 -*-
## About
# Add a mail as task to taskwarrior.
# Work in conjunction with taskopen script
# Based on https://github.com/artur-shaik/mutt2task
# Modified to include markdown extension and notmuch message ID integration
#
## Usage
# add this to your .muttrc:
# macro index,pager t "<pipe-message>mutt2task.py<enter>"

import os
import sys
import email
import re
import errno
import shutil
from email.header import decode_header
from subprocess import call, Popen, PIPE

def rollback():
    print("INFO: Rolling back incomplete task/note creation:")
    call(['task', 'rc.confirmation=off', 'undo'])

# Initialize home directory and notes folder
home_dir = os.path.expanduser('~')
notes_folder = os.path.join(home_dir, "Notes/tasknotes")  # Using the path from your taskopenrc

# Create notes directory if it doesn't exist
try:
    os.makedirs(notes_folder, mode=0o750, exist_ok=True)
except OSError as ose:
    print(f"ERR: Cannot create directory '{notes_folder}': {ose}")
    sys.exit(1)

# Read email message from stdin
message = sys.stdin.read()
message = email.message_from_string(message)

# Extract message content
body = None
html = None
for part in message.walk():
    if part.get_content_type() == "text/plain":
        if body is None:
            body = ""
        body += part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', 'ignore')
    elif part.get_content_type() == "text/html":
        if html is None:
            html = ""
        html += part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', 'ignore')

# Create temporary file
try:
    process = Popen(['mktemp'], stdout=PIPE, stderr=PIPE)
    tmpfile = process.communicate()[0].strip()
    if process.returncode != 0:
        raise OSError("Failed to create temporary file")
except Exception as e:
    print(f"ERR: Cannot create temporary file: {e}")
    sys.exit(1)

# Process content
out = ""
if html:
    try:
        with open(tmpfile, "wb") as f:
            f.write(html.encode('utf-8'))
        p1 = Popen(['cat', tmpfile], stdout=PIPE)
        p2 = Popen(['elinks', '--dump'], stdin=p1.stdout, stdout=PIPE)
        out = p2.communicate()[0]
        p1.stdout.close()
    except Exception as e:
        print(f"ERR: HTML processing failed: {e}")
        os.unlink(tmpfile)
        sys.exit(1)
else:
    out = body.encode('utf-8') if body else b""

# Write processed content to temporary file
try:
    with open(tmpfile, "wb") as f:
        f.write(out if isinstance(out, bytes) else out.encode('utf-8'))
except Exception as e:
    print(f"ERR: Cannot write to temporary file: {e}")
    os.unlink(tmpfile)
    sys.exit(1)

# Process subject
subject = message['Subject']
def decodeif(s, charset):
    if isinstance(s, bytes):
        return s.decode(charset or 'ASCII', 'ignore')
    return s

if subject:
    decoded_subject = decode_header(subject)
    subject = ' '.join([decodeif(t[0], t[1]) for t in decoded_subject])
else:
    subject = "E-Mail import: no subject specified."

# Create task
try:
    process = Popen(['task', 'add', '+email', '--', subject], stdout=PIPE, stderr=PIPE)
    out, err = process.communicate()
    if process.returncode != 0:
        print(f"ERR: Task creation failed: {err.decode()}")
        os.unlink(tmpfile)
        sys.exit(1)
    
    match = re.match(r"^Created task (\d+).*", out.decode())
    if not match:
        print("ERR: Could not parse task ID from output")
        os.unlink(tmpfile)
        sys.exit(1)
    
    task_id = match.group(1)
    print(match.string.strip())
    
    # Get task UUID
    uuid_process = Popen(['task', task_id, 'uuids'], stdout=PIPE, stderr=PIPE)
    uuid, err = uuid_process.communicate()
    uuid = uuid.strip().decode()
    if not uuid:
        print("ERR: Could not get task UUID")
        rollback()
        os.unlink(tmpfile)
        sys.exit(1)
    
    # Copy content to notes file with .md extension
    notes_file = os.path.join(notes_folder, f"{uuid}.md")
    try:
        shutil.copy(tmpfile, notes_file)
    except Exception as e:
        print(f"ERR: Cannot create notes file '{notes_file}': {e}")
        rollback()
        os.unlink(tmpfile)
        sys.exit(1)

    # Add annotation with full path to notes file including .md extension
    notes_path = os.path.join("~/Notes/tasknotes", f"{uuid}.md")  # Using relative to home for cleaner annotation
    annotation_process = Popen(['task', task_id, 'annotate', '--', notes_path], stdout=PIPE, stderr=PIPE)
    out, err = annotation_process.communicate()
    if annotation_process.returncode != 0:
        print(f"ERR: Cannot annotate task {task_id}: {err.decode()}")
        rollback()
        os.unlink(tmpfile)
        sys.exit(1)

    # Add message ID annotation
    message_id = message.get('Message-ID', '')
    if not message_id:
        message_id = message.get('message-id', '')  # Try lowercase variant
    
    if message_id:
        # Clean up message ID - remove any < > brackets
        message_id = message_id.strip('<>')
        email_ref = f"id:{message_id}"
        
        # Add the email reference annotation
        annotation_process = Popen(['task', task_id, 'annotate', '--', email_ref], stdout=PIPE, stderr=PIPE)
        out, err = annotation_process.communicate()
        if annotation_process.returncode != 0:
            print(f"WARN: Could not add email reference annotation: {err.decode()}")
    
finally:
    # Clean up temporary file
    try:
        os.unlink(tmpfile)
    except:
        pass

print(f"SUCCESS: Task {task_id} created with notes in {notes_file}")
