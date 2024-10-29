#!/usr/bin/env python3
import json
import subprocess
import argparse
from datetime import timedelta, datetime
from dateutil import parser as date_parser
from tabulate import tabulate
import logging

# Configure logging for debugging
logging.basicConfig(level=logging.ERROR, format='%(levelname)s: %(message)s')

# Set up argument parser
parser = argparse.ArgumentParser(description='Summarize Timewarrior entries.')
parser.add_argument('-p', '--period', choices=['day', 'yesterday', 'week', 'month', 'pastweek'], default='day',
                    help='Time period to summarize (default: day)')
args = parser.parse_args()

# Determine time period argument for timew
if args.period == 'yesterday':
    today_weekday = datetime.now().weekday()
    if today_weekday == 0:  # Monday
        timew_period_args = ['friday']
    else:
        timew_period_args = ['yesterday']
elif args.period == 'pastweek':
    today = datetime.now()
    # Find the most recent Monday (last week's Monday)
    last_monday = today - timedelta(days=today.weekday() + 7)
    last_friday = last_monday + timedelta(days=4)
    start_time = last_monday.strftime("%Y-%m-%dT00:00:00")
    end_time = last_friday.strftime("%Y-%m-%dT23:59:59")
    timew_period_args = [start_time, 'to', end_time]
else:
    timew_period_args = [f':{args.period}']

# Define task-specific tags that should be treated as tasks, not labels
task_specific_tags = {'break', 'meetings'}

# Define labels to exclude from being displayed and treated as tasks
exclude_labels = {'github', 'work', 'linear'}

# Run 'task all-projects' to get the complete list of projects (including closed ones)
# Define projects to exclude (case-insensitive)
exclude_projects = {'linear'}

# Run 'task all-projects' to get the complete list of projects (including closed ones)
try:
    result = subprocess.run(['task', 'all-projects'], capture_output=True, text=True, check=True)
    project_list = result.stdout.strip().split('\n')
    # Filter out excluded projects (case-insensitive)
    project_list = [
        proj.strip() 
        for proj in project_list 
        if proj.strip() and proj.strip().lower() not in exclude_projects
    ]
    project_list_lower = set(p.lower() for p in project_list)
    logging.debug(f"Projects: {project_list}")
except subprocess.CalledProcessError as e:
    logging.error("Error running 'task all-projects': " + str(e))
    project_list = []
    project_list_lower = set()
except FileNotFoundError:
    logging.error("Taskwarrior is not installed or not found in PATH.")
    exit(1)

# Run 'task _tags' to get the list of known labels, excluding task-specific tags and projects
try:
    result = subprocess.run(['task', '_tags'], capture_output=True, text=True, check=True)
    known_labels = set(result.stdout.strip().split('\n'))
    # Exclude task-specific tags, project names, and specified excluded labels
    known_labels = {
        tag.strip().lower() for tag in known_labels 
        if tag.strip().lower() not in task_specific_tags 
        and tag.strip().lower() not in project_list_lower
    }
    # Further exclude specific labels from being displayed
    known_labels -= exclude_labels
    logging.debug(f"Known labels (after exclusion): {known_labels}")
except subprocess.CalledProcessError as e:
    logging.error("Error running 'task _tags': " + str(e))
    known_labels = set()
except FileNotFoundError:
    logging.error("Taskwarrior is not installed or not found in PATH.")
    exit(1)

# Run 'timew export' with the specified period and capture the JSON output
try:
    # Prepare the command based on the period
    timew_command = ['timew', 'export'] + timew_period_args
    result = subprocess.run(timew_command, capture_output=True, text=True, check=True)
    # Parse the entire output as a single JSON array
    entries = json.loads(result.stdout)
    logging.debug(f"Number of entries parsed: {len(entries)}")
except subprocess.CalledProcessError as e:
    logging.error(f"Error running 'timew export {' '.join(timew_period_args)}': " + str(e))
    entries = []
except FileNotFoundError:
    logging.error("Timewarrior is not installed or not found in PATH.")
    exit(1)
except json.JSONDecodeError as e:
    logging.error("Error parsing JSON from 'timew export': " + str(e))
    logging.debug(f"JSON Output: {result.stdout}")
    entries = []

# Filter entries to only include those with the 'work' tag
entries = [
    entry for entry in entries
    if 'tags' in entry and 'work' in [tag.lower() for tag in entry['tags']]
]

# Function to format durations
def format_duration(td):
    hours, remainder = divmod(int(td.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours}h {minutes}m {seconds}s"

# Variables to store total durations
overall_total_duration = timedelta()
overall_total_breaks_duration = timedelta()
project_task_durations = {}

for entry in entries:
    if 'end' in entry:
        # Parse the start and end times
        try:
            start = date_parser.isoparse(entry['start'])
            end = date_parser.isoparse(entry['end'])
            duration = end - start
            overall_total_duration += duration
        except Exception as e:
            logging.error(f"Error parsing dates for entry ID {entry.get('id', 'Unknown')}: {e}")
            continue

        tags = entry.get('tags', [])
        # Initialize fields
        projects = []
        labels = set()
        tasks = []

        # Identify project tags
        for tag in tags:
            if tag.lower() in project_list_lower and tag.lower() not in exclude_projects:
                # Retrieve the original project name with correct casing
                original_project = next((p for p in project_list if p.lower() == tag.lower()), tag)
                projects.append(original_project)

        # Identify labels (excluding tags already identified as projects and task-specific tags)
        for tag in tags:
            tag_lower = tag.lower()
            if tag_lower in known_labels:
                labels.add(tag_lower)

        # Identify tasks (task-specific tags or any tags not in known_labels, not in projects, and not in exclude_labels)
        for tag in tags:
            tag_lower = tag.lower()
            if (tag_lower in task_specific_tags) or (
                tag_lower not in known_labels 
                and tag_lower not in project_list_lower 
                and tag_lower not in exclude_labels  # **Excluded Labels from Tasks**
            ):
                tasks.append(tag)

        # Use 'Unassigned' if no project is found
        project_name = ', '.join(sorted(projects)) if projects else 'Unassigned'
        task_name = ', '.join(sorted(tasks)) if tasks else '-'

        # Aggregate durations per project and task
        project_task_key = (project_name, task_name)
        if project_task_key not in project_task_durations:
            project_task_durations[project_task_key] = {
                'labels': set(),
                'duration': timedelta()
            }
        project_task_durations[project_task_key]['duration'] += duration
        project_task_durations[project_task_key]['labels'].update(labels)

        # Check if the entry is a break
        is_break = 'break' in (tag.lower() for tag in tags)

        if is_break:
            overall_total_breaks_duration += duration

# Prepare data for the table
project_summaries = {}
for (project_name, task_name), info in project_task_durations.items():
    duration = info['duration']
    # Exclude 'work' and any other undesired labels from displayed labels
    display_labels = info['labels']
    labels_str = ', '.join(sorted(display_labels)) if display_labels else '-'
    duration_str = format_duration(duration)

    # Aggregate durations per project
    if project_name not in project_summaries:
        project_summaries[project_name] = {
            'total_duration': timedelta(),
            'tasks': []
        }

    project_summaries[project_name]['total_duration'] += duration

    # Add task to project's task list
    project_summaries[project_name]['tasks'].append({
        'Labels': labels_str,
        'Task': task_name,
        'Duration': duration_str,
        'duration_td': duration
    })

# Build the table with summaries inline
table_data = []
for project_name in sorted(project_summaries.keys()):
    project = project_summaries[project_name]
    # Sort tasks within the project by duration (optional)
    # project['tasks'].sort(key=lambda x: x['duration_td'], reverse=True)

    for task in project['tasks']:
        table_data.append([
            project_name,
            task['Labels'],
            task['Task'],
            task['Duration']
        ])

    # Add summary row for the project
    total_duration = project['total_duration']
    duration_str = format_duration(total_duration)
    summary_text = f"Total for {project_name}: {duration_str}"
    table_data.append(['', '', summary_text, ''])
    # Add an empty row for spacing
    table_data.append(['', '', '', ''])

# Create the table
headers = ['Project', 'Labels', 'Task', 'Duration']
table = tabulate(table_data, headers, tablefmt='github')

# Format overall total durations
overall_total_duration_str = format_duration(overall_total_duration)
overall_total_breaks_duration_str = format_duration(overall_total_breaks_duration)
overall_total_without_breaks = overall_total_duration - overall_total_breaks_duration
overall_total_without_breaks_str = format_duration(overall_total_without_breaks)

# Output the table and overall totals
print(table)
print(f"\n**Overall total duration ({args.period}):** {overall_total_duration_str}")
print(f"**Overall total breaks duration ({args.period}):** {overall_total_breaks_duration_str}")
print(f"**Overall total duration without breaks ({args.period}):** {overall_total_without_breaks_str}")
