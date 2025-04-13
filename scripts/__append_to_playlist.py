#!/usr/bin/env python3
import sys
import logging
import os
import subprocess

logging.basicConfig(filename=os.path.expanduser('/home/decoder/logme.log'), level=logging.DEBUG)

def organize_with_claude(playlist_file_path):
    logging.debug(f'Calling Claude to organize playlist: {playlist_file_path}')
    
    try:
        with open(playlist_file_path, 'r') as f:
            playlist_content = f.read()
        
        prompt = f"""
You are an expert music curator tasked with organizing a playlist file.

Here's the current playlist content:

{playlist_content}

Please:
1. ANALYZE each entry to determine the most appropriate genre category
2. For entries with no clear genre tag (like entries about Firefox or other browsers), identify what type of content it is and assign an appropriate category
3. REFORMAT each entry to follow this pattern: # GENRE: Title
4. GROUP all entries by genre categories
5. SORT entries alphabetically within each genre group
6. Use ALL CAPS for genre tags for consistency (e.g., # AMBIENT:, # TECHNO:)
7. Preserve the exact YouTube URLs without modification
8. IMPORTANT: Preserve any existing star emoji (⭐) that marks favorite tracks
9. Convert any malformed entries to the proper format
10. IMPORTANT: Do not include any empty lines in your response - the playlist format should alternate between title lines and URL lines with no blank lines

Examples of correct formatting:
# AMBIENT: Forest Sounds
https://example.com/url

# TECHNO: ⭐ Dark Bass Mix
https://example.com/url2

Return ONLY the organized playlist content with no explanations or additional text.
Every line in your response will be written directly to the playlist file.
"""
        
        # Call Claude CLI with the prompt using full path
        result = subprocess.run(
            ['/home/decoder/.npm-global/bin/claude', '-p', prompt],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Get organized playlist from Claude's response
        organized_playlist = result.stdout
        
        # Remove any empty lines
        organized_lines = [line for line in organized_playlist.split('\n') if line.strip()]
        cleaned_playlist = '\n'.join(organized_lines)
        
        # Write the organized playlist back to the file
        with open(playlist_file_path, 'w') as f:
            f.write(cleaned_playlist)
        
        logging.debug('Playlist successfully organized by Claude')
        
    except Exception as e:
        import traceback
        logging.error(f'Error organizing playlist with Claude: {str(e)}')
        logging.error(f'Traceback: {traceback.format_exc()}')

def append_to_playlist(url, description, playlist_file_path):
    logging.debug(f'Appending URL: {url} with description: {description} to playlist: {playlist_file_path}')
    
    # Format entry properly preserving any existing genre tag
    if ":" in description and description.split(":", 1)[0].strip().upper() == description.split(":", 1)[0].strip():
        # Already has a genre tag, use it as is
        entry = f"# {description}\n{url}\n"
    else:
        # No genre tag, just add as is
        entry = f"# {description}\n{url}\n"
    
    with open(playlist_file_path, 'r') as f:
        existing_content = f.read()

    if url not in existing_content:
        with open(playlist_file_path, 'a') as f:
            f.write(entry)
        logging.debug('Entry appended successfully.')
        return True
    else:
        logging.debug('URL already exists in playlist.')
        return False

def main():
    if len(sys.argv) < 4:
        logging.error('Usage: __append_to_playlist.py <url> <description> <playlist_file_path>')
        sys.exit(1)

    url = sys.argv[1]
    description = sys.argv[2]
    playlist_file_path = os.path.expanduser(sys.argv[3])

    entry_added = append_to_playlist(url, description, playlist_file_path)
    
    # Always organize the playlist with Claude after appending
    organize_with_claude(playlist_file_path)
    
    logging.debug('Operation completed successfully.')

if __name__ == "__main__":
    main()

