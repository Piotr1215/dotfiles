import subprocess
import time
import pexpect

def write_to_file(description, url):
    with open('capture_data.txt', 'a') as f:
        f.write(f"{description};{url}\n")

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
    time.sleep(0.25)  # Allow some time for the clipboard operation to complete
    
    url = clipboard.get_clipboard()

    # If no text is selected, use the window title as the description
    if not description:
        description = active_window_title
    
    # Write captured data to file
    write_to_file(description, url)
    
    # Invoke plink function with the captured description and URL
    invoke_plink(description, url)
    #message = "The url '{}' and description '{}' were added".format(url, description)
    #dialog.info_dialog(title="Information", message=message)
    # Create a custom dialog box with Zenity
    options = ["No Task", "Create Task"]
    message = f"The url '{url}'\nwith description '{description}' was added.\n\nShould we create an idea task for it?"

    # Call list_menu to show the dialog
    exit_code, choice = dialog.list_menu(options, title="Choose an Action", message=message, default="No Task")

    # Process the choice
    if choice == "Create Task":
        subprocess.run(["/home/decoder/dev/dotfiles/scripts/__create_task.sh", description, "+idea"])

    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
