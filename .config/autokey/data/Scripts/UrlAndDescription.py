import subprocess
import time
import pexpect
from urllib.parse import urlparse
import os
from bs4 import BeautifulSoup
import requests
import openai

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

def append_to_playlist(url, description, playlist_file_path):
    # Read existing URLs from the playlist file
    with open(playlist_file_path, 'r') as f:
        existing_urls = f.readlines()

    # Remove any trailing newlines
    existing_urls = [line.strip() for line in existing_urls]

    # Check if the URL is already in the playlist
    if url not in existing_urls:
        # Append the URL to the playlist file
        with open(playlist_file_path, 'a') as f:
            f.write('# '+ description + '\n')
            f.write(url + '\n')

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
    try:
        description = clipboard.get_selection()
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

    options = ["Add Link", "Create Task", "Add to Playlist"]
    message = f"Would you like to add a pet link for '{description}' from '{domain}' domain, create a task, or add to MPV playlist?"
    exit_code, choices = dialog.list_menu_multi(options, title="Choose an Action", message=message, defaults=["Create Task"])

    # Check if the dialog was cancelled (exit code is 0 when OK is clicked)
    if exit_code == 0:
        if "Add Link" in choices or "Create Task" in choices:
            custom_description = get_custom_description(description)
            
        if "Add Link" in choices:
            invoke_plink(custom_description, url)
        
        if "Create Task" in choices:
            subprocess.run(["/home/decoder/dev/dotfiles/scripts/__create_task.sh", custom_description] + tags)
            
        # PROJECT: playlist
        if "Add to Playlist" in choices:
            if "youtube.com" in domain or "youtu.be" in domain:  # Check if the domain is YouTube
                append_to_playlist(url, description, haruna_playlist_path)
            else:
                print("The URL must be from YouTube to add to Haruna playlist.")

    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
