#!/usr/bin/env python3
import json

def process_parts(parts, role):
    result = []
    for part in parts:
        if role == "user":
            result.append("### Me:\n")
        else:
            result.append("### GPT:\n")
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
        content_parts = [f"# {title}\n\n"]
        for mapping in item["mapping"].values():
            if mapping["message"] is not None:
                role = mapping["message"]["author"]["role"]
                parts = mapping["message"]["content"]["parts"]
                content_parts.extend(process_parts(parts, role))
        content = "\n\n".join(content_parts)

        with open(file_name, 'w') as f:
            f.write(content)

input_file = 'conversations.json'  # Replace with the path to your JSON file
create_markdown_files(input_file)

