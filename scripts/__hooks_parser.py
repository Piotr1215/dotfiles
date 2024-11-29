#!/usr/bin/env python3
import sys
import ast
import re

def format_action(info):
   if info['action'] == 'open_url':
       return info['url']
   elif info['action'] == 'focus_and_maximize_window':
       return f"Open {info['class_name']}"
   return info['action']

def extract_automations(hook_file):
   with open(hook_file) as f:
       content = f.read()
   
   project_matches = re.findall(r'project == "(\w+)".*?\["xdg-open", "([^"]+)"\]', content, re.DOTALL)
   task_dict = re.search(r'TASK_ACTIONS = ({[\s\S]*?})\s*\n\s*for', content)
   task_actions = {}
   
   if task_dict:
       try:
           dict_str = task_dict.group(1).strip()
           task_actions = ast.literal_eval(dict_str)
       except (SyntaxError, ValueError) as e:
           print(f"Error parsing dictionary: {e}", file=sys.stderr)

   output = "# Taskwarrior Automations\n\n"
   output += "## Project-based\n\n"
   for project, url in project_matches:
       output += f"- **{project}**\n  - {url}\n"
   
   output += "\n## Task-based\n\n"
   for task, info in task_actions.items():
       action_text = format_action(info)
       output += f"- **{task}**\n  - {action_text}\n"
   
   return output

if __name__ == "__main__":
   print(extract_automations(sys.argv[1]))
