markdown_template = '''## Description

<!-- - tasks description
     - steps to solve
     - background and additional context
     - optionally As a [user], I want [functionality], so that I can [benefit].
-->

## Acceptance Criteria

- [ ]

<!-- how can someone test it and tell that the task is done -->

## Testing Criteria

- [ ]

<!-- observable and verifiable test steps for example
     - linking the Notion doc
     - link to working cloud resources to be verified, etc)
-->

## Related

<!-- patent issues, related and blockers -->
'''

# Set the clipboard content using AutoKey's built-in functionality
clipboard.fill_clipboard(markdown_template)

# Simulate a Shift+Insert to paste it
keyboard.send_keys("<shift>+<insert>")
