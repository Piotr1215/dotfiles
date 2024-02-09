#!/usr/bin/env python3
import json
import os

def process_parts(parts, role):
    result = []
    for part in parts:
        if role == "user":
            result.append("### Me:\n")
        else:
            result.append("### GPT:\n")
        
        # Check if part is a dict and extract the text content; otherwise, process as string
        if isinstance(part, dict):
            content = part.get('text', '').replace('\\n', '\n').strip()  # Adjust 'text' key as needed
        else:
            content = part.replace('\\n', '\n').strip()
            
        result.append(f"{content}\n")
    return result

def create_file_name(title):
    title = title[:25].replace(' ', '').replace('.', '').replace(':', '')
    file_name = f"{title}.md"
    return file_name

def create_markdown_files(input_file):
    with open(input_file, 'r') as f:
        data = json.load(f)

    for item in data:
        title = item.get("title")
        if title is None:
            continue

        file_name = create_file_name(title)
        directory = os.path.dirname(file_name)
        if directory and not os.path.exists(directory):
            os.makedirs(directory)

        content_parts = [f"# {title}\n\n"]
        for mapping in item["mapping"].values():
            message = mapping.get("message")
            if message is not None:
                content = message.get("content")
                if content is not None:
                    parts = content.get("parts")
                    if parts is not None:
                        role = message["author"]["role"]
                        content_parts.extend(process_parts(parts, role))
        content = "\n\n".join(content_parts)

        with open(file_name, 'w') as f:
            f.write(content)

input_file = 'conversations.json'  # Replace with the path to your JSON file
create_markdown_files(input_file)

