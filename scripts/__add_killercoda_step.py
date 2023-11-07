#!/usr/bin/env python3
import json
import os
import shutil

# Function to add a new step with background script
def add_step_with_background(steps, title):
    step_number = len(steps) + 1
    step_directory = f"step{step_number}"
    step_md_file = f"{step_directory}/step{step_number}.md"
    background_script = f"{step_directory}/background.sh"

    # Create directory and files
    os.mkdir(step_directory)
    open(step_md_file, 'w').close()
    open(background_script, 'w').close()
    os.chmod(background_script, 0o755)

    # Return the new step dictionary
    return {
        "title": title,
        "text": step_md_file,
        "background": background_script
    }

# Main function
def main():
    index_file = 'index.json'
    backup_file = 'index_backup.json'

    # Check for the presence of index.json
    if not os.path.isfile(index_file):
        print(f"The file {index_file} must be present in the directory.")
        return

    # Backup the index.json file
    shutil.copyfile(index_file, backup_file)

    # Load the index.json content
    with open(index_file, 'r', encoding='utf-8') as file:
        data = json.load(file)

    # Prompt for the title of the new step
    title = input("Enter the title for the new step: ")

    # Add the new step
    new_step = add_step_with_background(data['details']['steps'], title)
    data['details']['steps'].append(new_step)

    # Write the updated content back to index.json
    with open(index_file, 'w', encoding='utf-8') as file:
        json.dump(data, file, ensure_ascii=False, indent=4)

    print("New step with background script added successfully.")

# Run the main function
if __name__ == "__main__":
    main()

