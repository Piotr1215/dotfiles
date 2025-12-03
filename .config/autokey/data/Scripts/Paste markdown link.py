# Get selected text (description)
description = clipboard.get_selection()

# Get URL from clipboard
url = clipboard.get_clipboard()

# Combine into markdown link
combined = f"[{description}]({url})"

# Put result in clipboard and paste
clipboard.fill_clipboard(combined)
keyboard.send_keys('<shift>+<insert>')
