import subprocess
import time
import pexpect
from urllib.parse import urlparse

# Function to get custom task descriptions
def get_custom_description(default_description):
    command = f"zenity --entry --text 'Enter task description:' --title 'Task Description' --entry-text '{default_description}'"
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
    command_tag = "link"

    child = pexpect.spawn('pet new -t')
    child.expect('Command>')
    child.sendline(command_name)
    child.expect('Description>')
    child.sendline(command_description)
    child.expect('Tag>')
    child.sendline(command_tag)
    child.expect(pexpect.EOF)

# Main logic of the script
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

    # If no text is selected, use the window title as the description
    if not description:
        description = active_window_title
    
    # Invoke plink function with the captured description and URL
    invoke_plink(description, url)
    #message = "The url '{}' and description '{}' were added".format(url, description)
    #dialog.info_dialog(title="Information", message=message)
    # Create a custom dialog box with Zenity
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
        subprocess.run(["/home/decoder/dev/dotfiles/scripts/__create_task.sh", description, "+idea"])

    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
