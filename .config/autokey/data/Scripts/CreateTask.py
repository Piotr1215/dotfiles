import os
import subprocess

create_task_path = '/home/decoder/dev/dotfiles/scripts/__create_task.sh'

def show_debug_message(message):
    subprocess.run(f"zenity --info --text='{message}'", shell=True)

def create_task(url):
    command = f"zenity --entry --text 'Enter task description and attributes:' --title 'Task Description' --entry-text 'Description +label1 project:projectName' --width 400"
    try:
        task_input = subprocess.check_output(command, shell=True, text=True).strip()
        task_args = task_input.split()  # Split the input into separate arguments
        subprocess.run([create_task_path] + task_args, text=True)  # Pass the arguments as a list
        
    except subprocess.CalledProcessError as e:
        show_debug_message(f"Error: {e.output}")

# Get clipboard content
url = clipboard.get_clipboard()
create_task(url)

clipboard.fill_clipboard("")
clipboard.fill_selection("")