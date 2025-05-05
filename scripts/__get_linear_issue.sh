#!/usr/bin/env bash

# __get_linear_issue.sh
# Gets detailed information about a Linear issue by ID, including all comments
# 
# Usage: ./__get_linear_issue.sh <issue-id>
# Example: ./__get_linear_issue.sh eng-6666
#
# Notes:
#   - Requires LINEAR_API_KEY environment variable to be set
#   - Issue ID is case-insensitive (eng-6666 and ENG-6666 are equivalent)
#   - Returns a JSON object with all issue details and comments

set -eo pipefail
IFS=$'\n\t'

# Logger with timestamp
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# Sanitize output by replacing user names with generic identifiers
sanitize_output() {
    # Create a temporary directory for our processing
    local temp_dir
    temp_dir=$(mktemp -d)
    local input_file="${temp_dir}/input.json"
    local output_file="${temp_dir}/output.json"
    
    # Save input to file
    cat > "$input_file"
    
    # Create a python script for sanitization to handle special characters properly
    cat > "${temp_dir}/sanitize.py" << 'EOF'
#!/usr/bin/env python3
import json
import sys
import re

# Load the JSON data
with open(sys.argv[1], 'r') as f:
    data = json.load(f)

# Extract all names and emails
names = set()
emails = set()
def extract_identifiers(obj):
    if isinstance(obj, dict):
        # Extract names
        if 'name' in obj and obj['name'] is not None and isinstance(obj['name'], str):
            names.add(obj['name'])
        
        # Extract emails
        if 'email' in obj and obj['email'] is not None and isinstance(obj['email'], str):
            emails.add(obj['email'])
            # Also extract username part from email for comment mentions
            if '@' in obj['email']:
                username = obj['email'].split('@')[0]
                names.add(username)
        
        # Look through all keys
        for k, v in obj.items():
            extract_identifiers(v)
    elif isinstance(obj, list):
        for item in obj:
            extract_identifiers(item)

extract_identifiers(data)

# First create a consistent mapping for names and emails based on the same user
user_map = {}
email_to_id = {}
name_to_id = {}
next_id = 1

# Process user data to ensure consistent mapping
for obj in data.get('data', {}).get('issue', {}).get('comments', {}).get('nodes', []):
    if 'user' in obj and isinstance(obj['user'], dict):
        user = obj['user']
        user_id = user.get('id')
        
        if user_id and user_id not in user_map:
            user_map[user_id] = next_id
            next_id += 1
            
            # Map this user's name and email to the same ID
            if 'name' in user and user['name']:
                name_to_id[user['name']] = user_id
            if 'email' in user and user['email']:
                email_to_id[user['email']] = user_id

# Handle assignee
assignee = data.get('data', {}).get('issue', {}).get('assignee', {})
if assignee:
    user_id = assignee.get('id')
    if user_id and user_id not in user_map:
        user_map[user_id] = next_id
        next_id += 1
        
        # Map this user's name and email
        if 'name' in assignee and assignee['name']:
            name_to_id[assignee['name']] = user_id
        if 'email' in assignee and assignee['email']:
            email_to_id[assignee['email']] = user_id

# Create mappings for names and emails to ensure consistency
name_map = {}
email_map = {}

# First map names and emails with known users
for name, user_id in name_to_id.items():
    if user_id in user_map:
        name_map[name] = f"person{user_map[user_id]}"

for email, user_id in email_to_id.items():
    if user_id in user_map:
        email_map[email] = f"person{user_map[user_id]}@example.com"
        # Also map username from email
        if '@' in email:
            username = email.split('@')[0]
            name_map[username] = f"person{user_map[user_id]}"

# Handle remaining names and emails (non-user fields)
remaining_names = set(names) - set(name_map.keys())
remaining_emails = set(emails) - set(email_map.keys())

# Assign IDs to remaining names and emails
for name in sorted(remaining_names):
    name_map[name] = f"person{next_id}"
    next_id += 1

for email in sorted(remaining_emails):
    email_map[email] = f"person{next_id}@example.com"
    next_id += 1

# Replace names and emails in structured fields
def replace_names_in_fields(obj):
    if isinstance(obj, dict):
        # Replace name fields
        if 'name' in obj and obj['name'] in name_map:
            obj['name'] = name_map[obj['name']]
        
        # Replace email fields
        if 'email' in obj and obj['email'] in email_map:
            obj['email'] = email_map[obj['email']]
        
        # Special handling for comment bodies
        if 'body' in obj and isinstance(obj['body'], str):
            body = obj['body']
            
            # First handle @mentions
            for real_name, anon_name in name_map.items():
                # Replace @username with @personX
                body = re.sub(r'@' + re.escape(real_name) + r'\b', '@' + anon_name, body)
                # Also replace regular occurrences
                body = re.sub(r'\b' + re.escape(real_name) + r'\b', anon_name, body)
            
            # Then replace emails
            for real_email, anon_email in email_map.items():
                body = body.replace(real_email, anon_email)
                
            obj['body'] = body
            
        # Process all fields recursively
        for k, v in obj.items():
            obj[k] = replace_names_in_fields(v)
    elif isinstance(obj, list):
        return [replace_names_in_fields(item) for item in obj]
    return obj

# Apply sanitization
sanitized_data = replace_names_in_fields(data)

# Write the sanitized output
with open(sys.argv[2], 'w') as f:
    json.dump(sanitized_data, f, indent=2)
EOF

    # Make the script executable
    chmod +x "${temp_dir}/sanitize.py"
    
    # Run the sanitization
    "${temp_dir}/sanitize.py" "$input_file" "$output_file"
    
    # Output the sanitized result
    cat "$output_file"
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Validate necessary environment variables
validate_env_vars() {
    local required_vars=(LINEAR_API_KEY)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Error: Environment variable $var is not set." >&2
            exit 1
        fi
    done
}

# Get detailed information for a Linear issue by ID
get_linear_issue() {
    local issue_id="$1"
    
    if [[ -z "$issue_id" ]]; then
        echo "Error: Issue ID is required." >&2
        exit 1
    fi
    
    # Handle different issue ID formats
    # If only the numeric ID was provided, exit with error
    if [[ "$issue_id" =~ ^[0-9]+$ ]]; then
        echo "Error: Please provide a full issue ID with team prefix (e.g., ENG-123, DOC-456)" >&2
        exit 1
    fi
    
    # Convert ID to uppercase
    issue_id=$(echo "$issue_id" | tr '[:lower:]' '[:upper:]')
    
    # Make API call to get the specific issue with all details
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data '{"query": "query IssueWithComments($id: String!) { issue(id: $id) { id identifier title description url state { id name color } project { id name } team { id name key } assignee { id name email } labels { nodes { id name color } } priority createdAt updatedAt completedAt comments { nodes { id body user { id name } createdAt updatedAt } } } }", "variables": {"id": "'"$issue_id"'"}}' \
        https://api.linear.app/graphql | sanitize_output
}

# Main function
main() {
    validate_env_vars
    
    # Check if issue ID was provided
    if [[ $# -eq 0 ]]; then
        echo "Error: Please provide a Linear issue ID (e.g., ENG-123, DOC-456)" >&2
        exit 1
    fi
    
    local issue_id="$1"
    get_linear_issue "$issue_id"
}

# Execute main only if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
