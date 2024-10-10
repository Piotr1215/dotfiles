markdown_template = '''## Description

## Acceptance Criteria

- [ ]


## Related

- patent issues, related and blockers
'''

# Set the clipboard content using AutoKey's built-in functionality
clipboard.fill_clipboard(markdown_template)

# Simulate a Shift+Insert to paste it
keyboard.send_keys("<shift>+<insert>")

# Sleep to allow the paste to complete
time.sleep(0.1)

# Move the cursor up by 4 lines to place it right after '## Description'
keyboard.send_keys("<up>" * 4)
keyboard.send_keys("<enter>")
