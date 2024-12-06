# -*- coding: utf-8 -*-
import subprocess
import time

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
        dict or None: A dictionary containing the task description and selected project.
                    Returns None if the user cancels the dialog.
    """
    zenity_command = [
        "zenity",
        "--forms",
        "--title=New Task",
        "--text=Enter task details:",
        "--separator=|",
        "--add-entry=Description",
        "--add-combo=Project",
        f"--combo-values={'|'.join(projects)}"
    ]

    try:
        dialog_output = subprocess.check_output(zenity_command, stderr=subprocess.STDOUT, text=True).strip()
        fields = dialog_output.split('|')

        if len(fields) < 2:
            show_debug_message("Incomplete input received from Zenity dialog.")
            return None

        description, project = fields

        task_details = {
            "description": description.strip(),
            "project": project.strip()
        }

        return task_details

    except subprocess.CalledProcessError as e:
        if e.returncode == 1:
            show_debug_message("Zenity dialog was cancelled by the user.")
        else:
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
    projects = get_projects()
    if not projects:
        show_debug_message("No projects available to select.")
        return

    task = display_task_dialog(projects)
    if not task:
        return

    task_args = [
        task['description'],
        "+work",
        f"project:{task['project']}"
    ]

    try:
        subprocess.run([create_task_path] + task_args, check=True)
    except subprocess.CalledProcessError as e:
        show_debug_message(f"Error creating task:\n{e}")
    except Exception as e:
        show_debug_message(f"An unexpected error occurred while creating the task:\n{e}")

def main():
    """
    Main function to execute the task creation process.
    """
    clipboard.fill_clipboard("")
    keyboard.send_keys('yy')
    time.sleep(0.5)

    url = clipboard.get_clipboard().strip()
    if not url:
        show_debug_message("No URL found in the clipboard.")
        return

    create_task(url)
    clipboard.fill_clipboard("")
    clipboard.fill_selection("")

main()