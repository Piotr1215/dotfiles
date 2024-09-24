#!/usr/bin/env python3
import json
import subprocess
import argparse
from datetime import timedelta
from dateutil import parser as date_parser
from tabulate import tabulate

# Set up argument parser
parser = argparse.ArgumentParser(description='Summarize Timewarrior entries.')
parser.add_argument('-p', '--period', choices=['day', 'week', 'month'], default='day',
                    help='Time period to summarize (default: day)')
args = parser.parse_args()

# Determine time period argument for timew
timew_period = ':' + args.period

# Run 'task _projects' to get the list of projects
try:
    result = subprocess.run(['task', '_projects'], capture_output=True, text=True, check=True)
    project_list = result.stdout.strip().split('\n')
    project_list = [proj.strip() for proj in project_list if proj.strip()]
except subprocess.CalledProcessError as e:
    print("Error running 'task _projects':", e)
    project_list = []
except FileNotFoundError:
    print("Taskwarrior is not installed or not found in PATH.")
    exit(1)

# Define known labels (excluding 'work' from display)
known_labels = {'work', 'break', 'meeting', 'linear', 'next', 'call', 'subtask', 'automation', 'install', 'review'}

# Run 'timew export' with the specified period and capture the JSON output
try:
    result = subprocess.run(['timew', 'export', timew_period], capture_output=True, text=True, check=True)
    entries = json.loads(result.stdout)
except subprocess.CalledProcessError as e:
    print(f"Error running 'timew export {timew_period}':", e)
    entries = []
except FileNotFoundError:
    print("Timewarrior is not installed or not found in PATH.")
    exit(1)

# Function to format durations
def format_duration(td):
    hours, remainder = divmod(td.total_seconds(), 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{int(hours)}h {int(minutes)}m {int(seconds)}s"

# Variables to store total durations
overall_total_duration = timedelta()
overall_total_breaks_duration = timedelta()
project_task_durations = {}

for entry in entries:
    if 'end' in entry:
        # Parse the start and end times
        start = date_parser.isoparse(entry['start'])
        end = date_parser.isoparse(entry['end'])
        duration = end - start
        overall_total_duration += duration

        tags = entry['tags']
        # Initialize fields
        projects = []
        labels = set()
        tasks = []

        # Identify project tags
        for tag in tags:
            if tag in project_list:
                projects.append(tag)

        # Identify labels (excluding 'work' from display)
        for tag in tags:
            if tag in known_labels and tag != 'work':
                labels.add(tag)

        # Remaining tags are considered task descriptions
        for tag in tags:
            if tag not in projects and tag not in known_labels:
                tasks.append(tag)

        # Use 'Unassigned' if no project is found
        project_name = ', '.join(sorted(projects)) if projects else 'Unassigned'
        task_name = ', '.join(tasks) if tasks else '-'

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
        is_break = 'break' in labels

        if is_break:
            overall_total_breaks_duration += duration

# Prepare data for the table
table_rows = []
project_summaries = {}
for (project_name, task_name), info in project_task_durations.items():
    duration = info['duration']
    labels = ', '.join(sorted(info['labels'])) if info['labels'] else '-'
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
        'Labels': labels,
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
