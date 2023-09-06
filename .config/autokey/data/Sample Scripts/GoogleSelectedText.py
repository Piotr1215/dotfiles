import urllib.parse
import webbrowser

# Get the selected text
selected_text = clipboard.get_selection()

# URL-encode the text
encoded_text = urllib.parse.quote_plus(selected_text)

# Create the Google search URL
search_url = f"https://www.google.com/search?q={encoded_text}"

# Open the URL in the default web browser
webbrowser.open(search_url)
