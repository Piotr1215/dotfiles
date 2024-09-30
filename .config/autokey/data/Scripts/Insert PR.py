markdown_template = '''## Summary
<!-- Brief summary of the purpose of this PR -->

## Key Changes
<!-- List the key changes introduced in this PR -->

## Dependencies
<!-- Mention any PRs or tasks that need to be completed first -->

## TODO
<!-- Checklist of tasks that need to be done before merging -->

- [ ] task 1

<!-- Mention Linear issue the PR closes or fixes -->
Closes DOC-
'''

# Set the clipboard content using AutoKey's built-in functionality
clipboard.fill_clipboard(markdown_template)

# Sleep a little to avoid prepending the ! to text
time.sleep(0.2)

# Simulate a Shift+Insert to paste it
keyboard.send_keys("<shift>+<insert>")
