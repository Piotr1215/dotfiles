import os
import uuid
import subprocess
import time
from urllib.parse import urlparse

import pexpect
import requests
from bs4 import BeautifulSoup

envrc_path = os.path.expanduser('~/.envrc')
with open(envrc_path, 'r') as f:
    lines = f.readlines()
    
# Path to the Haruna playlist file
haruna_playlist_path = os.path.expanduser('~/haruna_playlist.m3u')

for line in lines:
    if line.startswith('export '):
        key_value_pair = line[7:].strip().split('=')
        if len(key_value_pair) == 2:
            key, value = key_value_pair
            os.environ[key] = value

def take_screenshot_interactively():
    # Simulate pressing the Print key
    time.sleep(0.5)
    subprocess.run(["xdotool", "key", "Print"])
    subprocess.run(["zenity", "--info", "--title=Screenshot", "--text=Screenshot taken."])

def save_screenshot_to_file(media_folder_path):
    # Generate a random filename for the screenshot
    screenshot_filename = f"{uuid.uuid4()}.png"
    screenshot_full_path = os.path.join(media_folder_path, screenshot_filename)

    # Save the screenshot from the clipboard to a file
    with open(screenshot_full_path, "wb") as f:
        subprocess.run(["xclip", "-selection", "clipboard", "-t", "image/png", "-o"], stdout=f)
    
    # Check if the screenshot was saved successfully
    if os.path.isfile(screenshot_full_path) and os.path.getsize(screenshot_full_path) > 0:
        return screenshot_full_path
    else:
        print("Failed to save screenshot.")
        return None

def append_to_web_highlights_with_screenshot(title, url, screenshot_full_path):
    web_highlights_path = '/home/decoder/dev/obsidian/decoder/Notes/webhighlights.md'
    relative_path_to_image = os.path.relpath(screenshot_full_path, os.path.dirname(web_highlights_path))

    # Append the title and a link to the screenshot in the web highlights markdown file
    content_to_append = f"\n## {title}\n\n![Screenshot]({relative_path_to_image})\n\nURL: {url}\n\n"
    
    with open(web_highlights_path, 'a') as f:
        f.write(content_to_append)

def get_website_description(url):
    try:
        response = requests.get(url)
        soup = BeautifulSoup(response.text, 'html.parser')
        meta_tag = soup.find('meta', {'name': 'description'}) or soup.find('meta', {'property': 'og:description'})

        if meta_tag:
            return meta_tag['content']
        else:
            return "No description available"
    except Exception as e:
        return f"An error occurred: {e}"

def get_custom_description(default_description):
    command = f"zenity --entry --text 'Enter task description:' --title 'Task Description' --entry-text '{default_description}' --width 400"
    try:
        task_description = subprocess.check_output(command, shell=True, text=True).strip()
        return task_description
    except subprocess.CalledProcessError:
        return None

def invoke_plink(description, url):
    if not url.startswith('http://') and not url.startswith('https://'):
        print("Not a valid URL.")
        return 1

    command_name = f"xdg-open \"{url}\""
    command_description = f"Link to {description}"

    # Convert tags to lowercase and remove the "+" prefix
    tags = ["web"]

    # Ensure the "link" tag is always present
    if "link" not in tags:
        tags.append("link")

    # Create a space-separated string of tags
    command_tag = " ".join(tags)

    child = pexpect.spawn('pet new -t')
    child.expect('Command>')
    child.sendline(command_name)
    child.expect('Description>')
    child.sendline(command_description)
    child.expect('Tag>')
    child.sendline(command_tag)
    child.expect(pexpect.EOF)

active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")

if 'Firefox' in active_window_title or 'Chrome' in active_window_title or 'Brave' in active_window_title:
    truncated_description = ""
    url = ""
    try:
        description = clipboard.get_selection()
        truncated_description = (description[:25] + '...') if len(description) > 25 else description
        time.sleep(0.25)
    except Exception:
        description = active_window_title

    clipboard.fill_clipboard("")  
    keyboard.send_keys('yy')
    time.sleep(0.5)

    url = clipboard.get_clipboard()
    website_description = get_website_description(url)
    tags = ["+web"]

    parsed_url = urlparse(url)
    domain = parsed_url.netloc

    if not description:
        description = active_window_title

    options = ["Add Link", "Create Task", "Add to Playlist", "Append to Web Highlights"]
    message = f"Would you like to add a pet link for '{truncated_description}' from '{domain}' domain, create a task, add to MPV playlist, or append to Web Highlights?"
    exit_code, choices = dialog.list_menu_multi(options, title="Choose an Action", message=message, defaults=["Append to Web Highlights"], height="220")

    # Check if the dialog was cancelled (exit code is 0 when OK is clicked)
    if exit_code == 0:
        if "Add Link" in choices or "Create Task" in choices:
            custom_description = get_custom_description(description)
            
        if "Add Link" in choices:
            invoke_plink(custom_description, url)
        
        if "Create Task" in choices:
            subprocess.run(["/home/decoder/dev/dotfiles/scripts/__create_task.sh", custom_description] + tags)
            
        if "Append to Web Highlights" in choices:
           media_folder_path = '/home/decoder/dev/obsidian/decoder/Notes/_media/'
           take_screenshot_interactively()
           screenshot_full_path = save_screenshot_to_file(media_folder_path)
           if screenshot_full_path:
               # Use the extension's shortcut to copy the selection as Markdown
               title = get_custom_description(description)
               # Now proceed to append the markdown formatted text to your file
               append_to_web_highlights_with_screenshot(title, url, screenshot_full_path)

            
        # PROJECT: playlist
        if "Add to Playlist" in choices:
            if "youtube.com" in domain or "youtu.be" in domain:  # Check if the domain is YouTube
                subprocess.run(["/home/decoder/dev/dotfiles/scripts/__append_to_playlist.py", url, active_window_title, haruna_playlist_path])
            else:
                print("The URL must be from YouTube to add to Haruna playlist.")

    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
