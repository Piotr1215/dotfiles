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

for line in lines:
    if line.startswith('export '):
        key_value_pair = line[7:].strip().split('=')
        if len(key_value_pair) == 2:
            key, value = key_value_pair
            os.environ[key] = value

openai.api_key = os.environ.get('OPENAI_API_KEY')

def sanitize_tags(raw_tags):
    if not isinstance(raw_tags, list):
        return ["+unknown"]
    
    sanitized_tags = []
    for tag in raw_tags:
        clean_tag = tag.replace("+", "")
        if clean_tag.isalnum():
            sanitized_tags.append(f"+{clean_tag}")
        else:
            return ["+unknown"]

    return sanitized_tags if sanitized_tags else ["+unknown"]

    
def get_tags_from_openai(description):
    prompt = f"Based on the provided website description: '{description}', please generate a list of up to 3 relevant tags for categorizing the content. Tags should have a maximum of 14 characters, include no special characters, and be words like +linux, +shopping, +pets. Please format the tags like this: +tag1, +tag2, +tag3, ..."
    
    chat_completion = openai.ChatCompletion.create(
        model="gpt-3.5-turbo",
        messages=[{
            "role": "user",
            "content": prompt
        }]
    )
    
    tags_output = chat_completion['choices'][0]['message']['content'] # type: ignore
    tags = tags_output.strip().split(", ")
    return sanitize_tags(tags)

def get_website_description(url):
    try:
        response = requests.get(url)
        soup = BeautifulSoup(response.text, 'html.parser')
        meta_tag = soup.find('meta', {'name': 'description'}) or soup.find('meta', {'property': 'og:description'})

        if meta_tag:
            return meta_tag['content'] # type: ignore
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

def invoke_plink(description, url, tags):
    if not url.startswith('http://') and not url.startswith('https://'):
        print("Not a valid URL.")
        return 1

    command_name = f"xdg-open \"{url}\""
    command_description = f"Link to {description}"
    command_tag = ",".join(tag[1:] for tag in tags)  # Remove the "+" from each tag and join them

    child = pexpect.spawn('pet new -t')
    child.expect('Command>')
    child.sendline(command_name)
    child.expect('Description>')
    child.sendline(command_description)
    child.expect('Tag>')
    child.sendline(command_tag)
    child.expect(pexpect.EOF)

active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")

if 'Firefox' in active_window_title:
    try:
        # Capture selected text
        description = clipboard.get_selection()
        time.sleep(0.25)
    except Exception:
        # If no text is selected, use the window title as the description
        description = active_window_title

    # Clear clipboard
    clipboard.fill_clipboard("")  
    
    # Capture URL separately
    keyboard.send_keys('yy')
    time.sleep(0.5)  # Allow some time for the clipboard operation to complete
    
    url = clipboard.get_clipboard()
    website_description = get_website_description(url)
    tags = get_tags_from_openai(website_description) 
    # If no text is selected, use the window title as the description
    if not description:
        description = active_window_title
    
    # Invoke plink function with the captured description and URL
    invoke_plink(description, url, tags)
    options = ["No Task", "Create Task"]
    parsed_url = urlparse(url)
    domain = parsed_url.netloc  # Extracts the domain from the URL
    message = f"Pet link created for '{description}' from '{domain}' domain.\n\nShould we create an idea task for it?\n"

    # Call list_menu to show the dialog
    exit_code, choice = dialog.list_menu(options, title="Choose an Action", message=message, default="No Task")

    # Process the choice
    if choice == "Create Task":
        # Get custom task description
        custom_description = get_custom_description(description)

        # If the custom description is provided, use it; otherwise, use the existing description logic
        description = custom_description if custom_description else description
        subprocess.run(["/home/decoder/dev/dotfiles/scripts/__create_task.sh", description] + tags)

    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
