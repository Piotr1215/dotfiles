#!/usr/bin/env python3
import json
import subprocess
import argparse
from datetime import timedelta, datetime
from dateutil import parser as date_parser
from tabulate import tabulate

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

# Run 'task _tags' to get the list of known labels
try:
    result = subprocess.run(['task', '_tags'], capture_output=True, text=True, check=True)
    known_labels = set(result.stdout.strip().split('\n'))
    known_labels = {tag.strip().lower() for tag in known_labels if tag.strip()}
    known_labels.add('break')  # Ensure 'break' is included
except subprocess.CalledProcessError as e:
    print("Error running 'task _tags':", e)
    known_labels = set()
    known_labels.add('break')
except FileNotFoundError:
    print("Taskwarrior is not installed or not found in PATH.")
    exit(1)

# Run 'timew export' with the specified period and capture the JSON output
try:
    # Prepare the command based on the period
    timew_command = ['timew', 'export'] + timew_period_args
    result = subprocess.run(timew_command, capture_output=True, text=True, check=True)
    entries = json.loads(result.stdout)
except subprocess.CalledProcessError as e:
    print(f"Error running 'timew export {' '.join(timew_period_args)}':", e)
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

        tags = entry.get('tags', [])
        # Initialize fields
        projects = []
        labels = set()
        tasks = []

        # Identify project tags
        for tag in tags:
            if tag in project_list:
                projects.append(tag)

        # Identify labels (excluding tags already identified as projects)
        for tag in tags:
            tag_lower = tag.lower()
            if tag_lower in known_labels and tag not in projects:
                labels.add(tag_lower)

        # Remaining tags are considered task descriptions
        for tag in tags:
            tag_lower = tag.lower()
            if tag_lower not in {p.lower() for p in projects} and tag_lower not in known_labels:
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
        is_break = 'break' in (tag.lower() for tag in tags)

        if is_break:
            overall_total_breaks_duration += duration

# Prepare data for the table
project_summaries = {}
for (project_name, task_name), info in project_task_durations.items():
    duration = info['duration']
    # Exclude 'work' from displayed labels
    display_labels = info['labels'] - {'work'}
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
