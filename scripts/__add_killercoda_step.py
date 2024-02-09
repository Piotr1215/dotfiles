#!/usr/bin/env python3
import os
import json
import subprocess
import difflib

def get_tree_output():
    # Get the current tree structure as a string
    result = subprocess.run(['tree'], stdout=subprocess.PIPE)
    return result.stdout.decode('utf-8')

def print_diff(old_tree, new_tree):
    # Use difflib to print a diff of the two tree outputs
    diff = difflib.unified_diff(
        old_tree.splitlines(keepends=True),
        new_tree.splitlines(keepends=True),
        fromfile='Before changes',
        tofile='After changes',
    )
    print(''.join(diff), end="")

# 1. Traverse the current directory and build a dictionary mapping step numbers to paths
def get_current_steps_dict():
    steps_dict = {}
    for item in os.listdir('.'):
        if item.startswith('step') and (os.path.isdir(item) or item.endswith('.md')):
            # Extract the step number from the name
            try:
                step_num = int(item.replace('step', '').replace('.md', ''))
                steps_dict[step_num] = item
            except ValueError:
                pass  # This handles cases where the step name is not a number
    return steps_dict

# 2. Take input from the user for the new step's name and the desired step number
def get_user_input(steps_dict):
    step_title = input("Enter the title for the new step: ")
    highest_step_num = max(steps_dict.keys(), default=0)
    
    while True:
        try:
            step_number = int(input(f"Enter the step number to insert the new step at (1-{highest_step_num+1}): "))
            if 1 <= step_number <= highest_step_num + 1:
                break
            else:
                print(f"Please enter a valid step number between 1 and {highest_step_num+1}.")
        except ValueError:
            print("That's not a valid number. Please try again.")
    
    return step_title, step_number

# 3. Determine the renaming and shifting required based on user input
def plan_renaming(steps_dict, insert_step_num):
    # Sort the keys to ensure we rename in the correct order
    sorted_step_nums = sorted(steps_dict.keys())
    renaming_plan = []
    
    # Determine which steps need to be shifted
    for step_num in sorted_step_nums:
        if step_num >= insert_step_num:
            renaming_plan.append((steps_dict[step_num], f"step{step_num + 1}"))
    
    # Reverse the plan to avoid overwriting any steps
    renaming_plan.reverse()
    return renaming_plan

def execute_renaming_plan(renaming_plan):
    # Execute the renaming plan
    for old_name, new_name in renaming_plan:
        # Make the new directory if it doesn't exist
        os.makedirs(new_name, exist_ok=True)
        # If it's a directory, we need to check for background.sh and foreground.sh
        if os.path.isdir(old_name):
            # Check and move background.sh if it exists
            old_background = f"{old_name}/background.sh"
            new_background = f"{new_name}/background.sh"
            if os.path.isfile(old_background):
                os.rename(old_background, new_background)
            # Check and move foreground.sh if it exists
            old_foreground = f"{old_name}/foreground.sh"
            new_foreground = f"{new_name}/foreground.sh"
            if os.path.isfile(old_foreground):
                os.rename(old_foreground, new_foreground)
            # Rename the step markdown file
            old_step_md = f"{old_name}/step{old_name.replace('step', '')}.md"
            new_step_md = f"{new_name}/step{new_name.replace('step', '')}.md"
            if os.path.isfile(old_step_md):
                os.rename(old_step_md, new_step_md)
        else:
            # If it's just a markdown file without a directory
            new_step_md = f"{new_name}.md"
            os.rename(old_name, new_step_md)

def add_new_step_file(insert_step_num, step_title):
    # Add the new step folder and files
    new_step_folder = f"step{insert_step_num}"
    new_step_md = f"{new_step_folder}/step{insert_step_num}.md"
    new_step_background = f"{new_step_folder}/background.sh"
    new_step_foreground = f"{new_step_folder}/foreground.sh"

    os.makedirs(new_step_folder, exist_ok=True)
    
    # Write the step markdown file
    with open(new_step_md, 'w') as md_file:
        md_file.write(f"# {step_title}\n")
    
    # Write a simple echo command to the background and foreground scripts
    script_content = f"#!/bin/sh\necho \"{step_title} script\"\n"
    
    with open(new_step_background, 'w') as bg_file:
        bg_file.write(script_content)
    with open(new_step_foreground, 'w') as fg_file:
        fg_file.write(script_content)
    
    os.chmod(new_step_background, 0o755)
    os.chmod(new_step_foreground, 0o755)

def update_index_json(steps_dict, insert_step_num, step_title, index_file):
    # Load the index.json file
    with open(index_file, 'r') as file:
        data = json.load(file)

    # Create new step entry
    new_step_data = {
        "title": step_title,
        "text": f"step{insert_step_num}/step{insert_step_num}.md",
        "background": f"step{insert_step_num}/background.sh"
    }

    # Insert the new step data into the steps list
    data['details']['steps'].insert(insert_step_num - 1, new_step_data)

    # Update the step numbers in the JSON structure
    for i in range(insert_step_num, len(data['details']['steps'])):
        step = data['details']['steps'][i]
        step_number = i + 1  # Convert to 1-based index
        step["text"] = f"step{step_number}/step{step_number}.md"
        step["background"] = f"step{step_number}/background{step_number}.sh"

    # Write the updated data back to index.json
    with open(index_file, 'w') as file:
        json.dump(data, file, ensure_ascii=False, indent=4)

def main():
    # Main execution
    old_tree_output = get_tree_output()
    steps_dict = get_current_steps_dict()
    step_title, insert_step_num = get_user_input(steps_dict)
    renaming_plan = plan_renaming(steps_dict, insert_step_num)

    # Execute the renaming plan
    execute_renaming_plan(renaming_plan)

    # Add the new step
    add_new_step_file(insert_step_num, step_title)

    # Update the index.json
    index_file = 'index.json'
    update_index_json(steps_dict, insert_step_num, step_title, index_file)
    new_tree_output = get_tree_output()
    # Print out the new file structure for confirmation
    print("\nNew file structure:")
    print_diff(old_tree_output, new_tree_output)
if __name__ == "__main__":
    main()
