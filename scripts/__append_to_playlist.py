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
You are an expert music curator tasked with organizing a playlist file with detailed mood-based classifications.

Here's the current playlist content:

{playlist_content}

Please:
1. ANALYZE each entry to determine the most appropriate genre AND mood category
2. For entries with no clear genre tag (like entries about Firefox or other browsers), identify what type of content it is and assign an appropriate category
3. REFORMAT each entry to follow this pattern: # GENRE/MOOD: Title
4. GROUP all entries by genre and mood categories
5. SORT entries alphabetically within each category group
6. Use ALL CAPS for genre and mood tags for consistency

Use these detailed mood categories (and create similar ones when needed):
- For AMBIENT music: AMBIENT/CALM, AMBIENT/DARK, AMBIENT/DREAMY, AMBIENT/ETHEREAL, AMBIENT/NATURE
- For ELECTRONIC music: ELECTRONIC/UPBEAT, ELECTRONIC/CHILL, ELECTRONIC/EXPERIMENTAL
- For FOCUS music: FOCUS/DEEP, FOCUS/LIGHT, FOCUS/CODING
- For INSTRUMENTAL: INSTRUMENTAL/PIANO, INSTRUMENTAL/GUITAR, INSTRUMENTAL/ORCHESTRAL
- For LOFI: LOFI/JAZZ, LOFI/HIPHOP, LOFI/CHILL
- For non-music content: TUTORIAL/DEV, TALK/TECH, TALK/PHILOSOPHY, etc.

Additional instructions:
7. Preserve the exact YouTube URLs without modification
8. IMPORTANT: Preserve any existing star emoji (⭐) that marks favorite tracks
9. Convert any malformed entries to the proper format
10. IMPORTANT: Do not include any empty lines in your response - the playlist format should alternate between title lines and URL lines with no blank lines

Examples of correct formatting:
# AMBIENT/NATURE: Forest Sounds
https://example.com/url

# ELECTRONIC/UPBEAT: ⭐ Dance Mix
https://example.com/url2

# FOCUS/CODING: Programming Session Music
https://example.com/url3

# LOFI/CHILL: Rainy Day Beats
https://example.com/url4

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
    
    # Format entry properly preserving any existing genre/mood tag
    if ":" in description:
        # Check if it has a proper GENRE/MOOD format or just GENRE format
        category_part = description.split(":", 1)[0].strip()
        if category_part.upper() == category_part:
            # Already has a genre or genre/mood tag, use it as is
            entry = f"# {description}\n{url}\n"
        else:
            # Has a colon but not in the right format
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
    # Check for reorganize-only mode
    if len(sys.argv) == 3 and sys.argv[1] == "--reorganize":
        playlist_file_path = os.path.expanduser(sys.argv[2])
        logging.debug(f'Reorganizing playlist without adding new entry: {playlist_file_path}')
        organize_with_claude(playlist_file_path)
        logging.debug('Reorganization completed successfully.')
        return
    
    if len(sys.argv) < 4:
        logging.error('Usage: __append_to_playlist.py <url> <description> <playlist_file_path>')
        logging.error('       __append_to_playlist.py --reorganize <playlist_file_path>')
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

