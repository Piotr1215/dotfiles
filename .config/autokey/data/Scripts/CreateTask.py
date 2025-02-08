# -*- coding: utf-8 -*-
import subprocess
import time

create_task_path = '/home/decoder/dev/dotfiles/scripts/__create_task.sh'

def show_debug_message(message):
    subprocess.run(['zenity', '--info', '--text', message, '--width=400', '--height=200'])

def get_projects():
    try:
        projects_output = subprocess.check_output(['task', '_projects'], text=True).strip()
        return projects_output.split('\n')
    except subprocess.CalledProcessError as e:
        show_debug_message(f"Error retrieving projects:\n{e.output}")
        return []
    except Exception as e:
        show_debug_message(f"Unexpected error retrieving projects:\n{e}")
        return []

def get_description(default_text=""):
    try:
        command = ["zenity", "--entry", 
                  "--title=Task Description",
                  "--text=Enter task description:",
                  "--entry-text=" + default_text,
                  "--width=600"]
        return subprocess.check_output(command, text=True).strip()
    except subprocess.CalledProcessError:
        return None

def get_project(projects):
    try:
        command = ["zenity", "--list",
                  "--title=Select Project",
                  "--text=Choose project:",
                  "--column=Project",
                  "--width=400",
                  "--height=400"] + projects
        return subprocess.check_output(command, text=True).strip()
    except subprocess.CalledProcessError:
        return None

def create_task(url, selected_text=""):
    projects = get_projects()
    if not projects:
        show_debug_message("No projects available.")
        return

    description = get_description(selected_text)
    if not description:
        return

    project = get_project(projects)
    if not project:
        return

    # Determine the tag based on the project name
    if project.startswith("home"):
        task_args = [description, "+home", f"project:{project}"]
    else:
        task_args = [description, "+work", f"project:{project}"]
    
    try:
        subprocess.run([create_task_path] + task_args, check=True)
    except subprocess.CalledProcessError as e:
        show_debug_message(f"Error creating task:\n{e}")
    except Exception as e:
        show_debug_message(f"An unexpected error occurred:\n{e}")

def main():
    try:
        selected_text = clipboard.get_selection()
        time.sleep(0.25)
    except Exception:
        selected_text = ""

    clipboard.fill_clipboard("")
    keyboard.send_keys('yy')
    time.sleep(0.5)
    
    url = clipboard.get_clipboard().strip()
    if not url:
        show_debug_message("No URL found in clipboard.")
        return

    create_task(url, selected_text)
    
    clipboard.fill_clipboard("")
    clipboard.fill_selection("")

main()