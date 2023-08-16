#!/usr/bin/env python3

import subprocess
import re
from collections import defaultdict

# Mapping of shorthand project names to their full descriptions
project_descriptions = {
    "perf": "Performance CI pipeline",
    "cfn": "Composition Functions",
    "platform": "Platform related",
    "uxp-prr": "UXP PRR",
    "swallow": "Project swallow",
    "": "None"
}

# Read the data from standard input
data = subprocess.check_output(["task", "current"]).decode('utf-8').strip().split("\n")

# Skip the header and separator lines
data = data[2:]

# Dictionary to group tasks by project
tasks_by_project = defaultdict(list)

for line in data:
    # Ignore the summary line
    if "tasks" in line:
        continue
    
    # Check if line starts a new task
    match = re.match(r'^\d+\s+\S+\s+(\S+)', line)
    if match:
        project = match.group(1)
        description = " ".join(line.split()[4:-1])
        tasks_by_project[project].append(description.strip())
    else:
        # Append the continuation of the description to the last task
        tasks_by_project[project][-1] += " " + line.strip()

# Print the results
for project, tasks in tasks_by_project.items():
    print(project_descriptions.get(project, project))  # Translate project code to name
    for task in tasks:
        print(f"- [ ] {task}")
    print()
