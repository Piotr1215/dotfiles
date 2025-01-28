markdown_template = '''## Summary
<!-- Brief summary of the purpose of this PR -->
Workflows triggers cleanup as per https://www.notion.so/loftsh/GitHub-Actions-Usage-17410940806980328e0ac12ccc0fb2de

<!-- Mention Linear issue the PR closes or fixes -->
References OPS-42
'''

# Set the clipboard content using AutoKey's built-in functionality
clipboard.fill_clipboard(markdown_template)

# Sleep a little to avoid prepending the ! to text
time.sleep(0.2)

# Simulate a Shift+Insert to paste it
keyboard.send_keys("<shift>+<insert>")
