#!/usr/bin/env python3

import sys
import json
import subprocess


def main():
    # Read the 'before' and 'after' task from stdin
    before_json = sys.stdin.readline()
    after_json = sys.stdin.readline()

    # Parse JSON
    try:
        before = json.loads(before_json)
        after = json.loads(after_json)
    except json.JSONDecodeError:
        # Exit silently if JSON parsing fails
        sys.exit(0)

    # Check the 'start' attribute
    before_has_start = "start" in before
    after_has_start = "start" in after

    # Get the task description
    description = after.get("description", "").lower()

    # Define a mapping from task descriptions to actions
    TASK_ACTIONS = {
        "meeting with denise": {
                    "action": "open_url",
                    "url": "https://docs.google.com/document/d/1sxvdDxMQPFfOWWHxMg8CfdFzhtrqQIeDVFOIuSgRvqk/edit?tab=t.0#heading=h.2ynhnu3nsbfx",
                },
        "fill daily hours": {
            "action": "open_url",
            "url": "https://docs.google.com/spreadsheets/d/1PNuxU3c-RCRGDMaVLftjCTkIBYxCGJNUMhqjFeGddvQ/edit?gid=407666270#gid=407666270",
        },
        "fill eng presentation": {
            "action": "open_url",
            "url": "https://drive.google.com/drive/folders/16RirnEug8fA2WztbbSiVS-0x_vXQpxGO",
        },
        "check github notifications": {
            "action": "open_url",
            "url": "https://github.com/notifications",
        },
        "respond to slack messages": {
            "action": "focus_and_maximize_window",
            "class_name": "Slack",
        },
        # Add more tasks and actions here
    }

    # Check if the description matches any task in the map
    for task_name, task_info in TASK_ACTIONS.items():
        if task_name in description:
            if not before_has_start and after_has_start:
                # Task was started
                action = task_info.get("action")

                if action == "open_url":
                    url = task_info.get("url")
                    if url:
                        # Open the URL
                        subprocess.Popen(
                            ["xdg-open", url],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                        # Focus on Firefox window using xdotool
                        subprocess.Popen(
                            [
                                "xdotool",
                                "search",
                                "--sync",
                                "--onlyvisible",
                                "--class",
                                "Firefox",
                                "windowactivate",
                            ],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                elif action == "focus_and_maximize_window":
                    class_name = task_info.get("class_name")
                    if class_name:
                        # Get the window ID(s) with the given class name
                        proc = subprocess.Popen(
                            [
                                "xdotool",
                                "search",
                                "--onlyvisible",
                                "--class",
                                class_name,
                            ],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL,
                            text=True,
                        )
                        window_ids, _ = proc.communicate()
                        window_ids = window_ids.strip().split()
                        if window_ids:
                            window_id = window_ids[0]
                            # Activate the window
                            subprocess.Popen(
                                ["xdotool", "windowactivate", "--sync", window_id],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                            )
                            # Maximize the window
                            subprocess.Popen(
                                [
                                    "xdotool",
                                    "windowactivate",
                                    window_id,
                                    "windowsize",
                                    window_id,
                                    "100%",
                                    "100%",
                                ],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                            )
                # Add more action types if needed

            # Exit after handling the task
            break

    # Output the 'after' task unmodified
    print(json.dumps(after))


if __name__ == "__main__":
    main()
