markdown_template ='piotrzan@gmail.com'

# Set the clipboard content using AutoKey's built-in functionality
clipboard.fill_clipboard(markdown_template)

# Sleep a little to avoid prepending the ! to text
time.sleep(0.2)

# Simulate a Shift+Insert to paste it
keyboard.send_keys("<shift>+<insert>")
