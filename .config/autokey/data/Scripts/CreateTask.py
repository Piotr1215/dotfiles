# -*- coding: utf-8 -*-
import subprocess
import time

# Define the path to the create_task shell script
create_task_path = '/home/decoder/dev/dotfiles/scripts/__create_task.sh'

def show_debug_message(message):
    """
    Displays a debug message using Zenity info dialog.

    Args:
        message (str): The message to display.
    """
    subprocess.run(['zenity', '--info', '--text', message])

def get_projects():
    """
    Retrieves the list of projects by executing the 'task _projects' command.

    Returns:
        list: A list of project names.
    """
    try:
        projects_output = subprocess.check_output(['task', '_projects'], text=True).strip()
        projects = projects_output.split('\n')
        return projects
    except subprocess.CalledProcessError as e:
        show_debug_message(f"Error retrieving projects:\n{e.output}")
        return []
    except Exception as e:
        show_debug_message(f"Unexpected error retrieving projects:\n{e}")
        return []

def display_task_dialog(projects):
    """
    Displays a Zenity form dialog to collect task details.

    Args:
        projects (list): A list of project names to populate the dropdown.

    Returns:
        dict or None: A dictionary containing the task description, category (Work/Home), and selected project.
                      Returns None if the user cancels the dialog.
    """
    # Prepare the Zenity command
    zenity_command = [
        "zenity",
        "--forms",
        "--title=New Task",
        "--text=Enter task details:",
        "--separator=|",
        "--add-entry=Description",
        "--add-combo=Category",
        "--combo-values=Work|Home",
        "--add-combo=Project",
        f"--combo-values={'|'.join(projects)}"
    ]

    try:
        # Execute the Zenity command and capture the output
        dialog_output = subprocess.check_output(zenity_command, stderr=subprocess.STDOUT, text=True).strip()

        # Parse the output
        fields = dialog_output.split('|')

        if len(fields) < 3:
            show_debug_message("Incomplete input received from Zenity dialog.")
            return None

        description, category, project = fields

        task_details = {
            "description": description.strip(),
            "category": category.strip(),
            "project": project.strip()
        }

        return task_details

    except subprocess.CalledProcessError as e:
        # User cancelled the dialog or an error occurred
        if e.returncode == 1:
            # User cancelled the dialog
            show_debug_message("Zenity dialog was cancelled by the user.")
        else:
            # Other errors
            show_debug_message(f"Zenity encountered an error:\n{e.output}")
        return None
    except Exception as e:
        show_debug_message(f"An unexpected error occurred while displaying the Zenity dialog:\n{e}")
        return None

def create_task(url):
    """
    Creates a new task by collecting details via Zenity dialog and executing the create_task shell script.

    Args:
        url (str): The URL to associate with the task.
    """
    # Retrieve the list of projects
    projects = get_projects()
    if not projects:
        show_debug_message("No projects available to select.")
        return

    # Display the Zenity dialog to collect task details
    task = display_task_dialog(projects)
    if not task:
        # User cancelled the dialog or an error occurred
        return

    # Prepare the arguments for the create_task shell script
    # Convert category to label (e.g., 'Work' to '+work')
    category_label = f"+{task['category'].lower()}"

    # Convert project to 'project:projectName'
    project_arg = f"project:{task['project']}"

    # Prepare the arguments list
    task_args = [
        task['description'],
        category_label,
        project_arg
    ]

    try:
        # Execute the create_task shell script with the collected arguments
        subprocess.run([create_task_path] + task_args, check=True)
    except subprocess.CalledProcessError as e:
        show_debug_message(f"Error creating task:\n{e}")
    except Exception as e:
        show_debug_message(f"An unexpected error occurred while creating the task:\n{e}")

def main():
    """
    Main function to execute the task creation process.
    """
    # Clear the clipboard
    clipboard.fill_clipboard("")

    # Send 'yy' to copy the URL (ensure 'yy' is correctly set up in your environment)
    keyboard.send_keys('yy')

    # Wait for the clipboard to be populated
    time.sleep(0.5)

    # Retrieve the URL from the clipboard
    url = clipboard.get_clipboard().strip()

    if not url:
        show_debug_message("No URL found in the clipboard.")
        return

    # Create the task with the retrieved URL
    create_task(url)

    # Clear the clipboard after processing
    clipboard.fill_clipboard("")
    clipboard.fill_selection("")

# Execute the main function
main()
