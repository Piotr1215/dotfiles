#!/usr/bin/env python3
import argparse
import importlib.util
import logging
import os
import subprocess
import tempfile
import pathlib
from logging.handlers import TimedRotatingFileHandler
import sys

# Set up logging with timestamp and rotation
log_file = pathlib.Path.home() / 'logme.log'
handler = TimedRotatingFileHandler(
    filename=log_file,
    when='D',
    interval=7,
    backupCount=4
)
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[handler]
)

# Configuration settings
# Claude CLI path - read from environment or use default
CLAUDE_BIN = os.environ.get('CLAUDE_BIN', '/home/decoder/.npm-global/bin/claude')

# Maximum number of lines in a playlist before warning about token limits
MAX_PLAYLIST_LINES = 2000

# Try to load prompt from an external file if it exists, otherwise use built-in prompt
PROMPT_FILE = pathlib.Path(__file__).parent / 'playlist_prompt.md'

# Claude prompt template stored separately for easier maintenance
CLAUDE_PROMPT = """
You are an expert music curator tasked with organizing a playlist file with detailed artist and mood-based classifications.

Here's the current playlist content:

{playlist_content}

Please:
1. ANALYZE each entry to determine:
   - The most appropriate genre AND mood category
   - The artist name when possible
2. For entries with no clear genre tag (like entries about Firefox or other browsers), identify what type of content it is and assign an appropriate category
3. REFORMAT each entry to follow this pattern: # GENRE/MOOD [ARTIST]: Title
4. GROUP all entries first by genre and mood categories, then by artist
5. SORT entries alphabetically within each artist group
6. Use ALL CAPS for genre/mood tags and [ARTIST] tags for consistency

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
10. If the artist cannot be determined, omit the artist tag entirely
11. IMPORTANT: Do not include any empty lines in your response - the playlist format should alternate between title lines and URL lines with no blank lines

Examples of correct formatting:
# AMBIENT/NATURE [FOREST RECORDINGS]: Forest Sounds
https://example.com/url

# ELECTRONIC/UPBEAT [DAFT PUNK]: ⭐ Dance Mix
https://example.com/url2

# FOCUS/CODING [LOFI GIRL]: Programming Session Music
https://example.com/url3

# LOFI/CHILL: Rainy Day Beats (no artist identified)
https://example.com/url4

# TUTORIAL/DEV [FIRESHIP]: JavaScript Tips
https://example.com/url5

IMPORTANT: Return ONLY the organized playlist content starting with "#" characters.
DO NOT include ANY introductory text like "Here's your organized playlist:" 
DO NOT include ANY explanations or additional text.
Start IMMEDIATELY with the first "# GENRE/MOOD" line.
Every line in your response will be written directly to the playlist file.
"""

def atomic_write(file_path, content):
    """
    Write content to a file atomically using a temporary file to prevent data loss.
    Ensures cleanup of temporary files even on exceptions.
    """
    path = pathlib.Path(file_path)
    tmp_path = None
    
    try:
        # Create a temporary file in the same directory as the target file
        with tempfile.NamedTemporaryFile('w', delete=False, dir=path.parent, suffix='.tmp') as tmp:
            tmp.write(content)
            tmp_path = pathlib.Path(tmp.name)
        
        # Replace the original file with the temporary file
        tmp_path.replace(path)
        logging.debug(f'Atomically wrote content to {file_path}')
    finally:
        # Clean up the temporary file if it still exists (e.g., after an exception)
        if tmp_path and tmp_path.exists():
            tmp_path.unlink(missing_ok=True)

def load_prompt_template():
    """
    Load the prompt template from an external file if available,
    otherwise use the built-in template.
    """
    if PROMPT_FILE.exists():
        try:
            logging.debug(f"Loading prompt template from {PROMPT_FILE}")
            return PROMPT_FILE.read_text()
        except Exception as e:
            logging.warning(f"Failed to load prompt from {PROMPT_FILE}: {e}")
    
    # Fall back to built-in template
    return CLAUDE_PROMPT

def organize_with_claude(playlist_file_path, dry_run=False):
    """
    Reorganize a playlist file using Claude, with atomic write and better error handling.
    """
    logging.debug(f'Calling Claude to organize playlist: {playlist_file_path}')
    
    try:
        # Read the playlist content
        playlist_content = pathlib.Path(playlist_file_path).read_text()
        
        # Check if playlist is too large for Claude's context window
        line_count = len(playlist_content.splitlines())
        if line_count > MAX_PLAYLIST_LINES:
            logging.warning(f"Playlist has {line_count} lines, which may exceed Claude's token limit")
            print(f"WARNING: Playlist has {line_count} lines, which exceeds the recommended limit of {MAX_PLAYLIST_LINES}.")
            print("This may cause Claude to truncate or fail to process the playlist correctly.")
            print("Consider splitting the playlist into smaller files.")
            
            if not dry_run:
                user_input = input("Continue anyway? (y/n): ")
                if user_input.lower() != 'y':
                    logging.info("User aborted organization due to playlist size")
                    return False
        
        # Load the prompt template from file or built-in
        prompt_template = load_prompt_template()
        
        # Format the prompt with the playlist content
        prompt = prompt_template.format(playlist_content=playlist_content)
        
        # Call Claude CLI with retries, backoff, and timeout
        max_retries = 3
        timeout = 90  # seconds
        backoff_factor = 2
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                logging.debug(f'Calling Claude (attempt {retry_count + 1}/{max_retries})')
                result = subprocess.run(
                    [CLAUDE_BIN, '-p', prompt],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=timeout
                )
                break  # Success, exit the loop
            except subprocess.TimeoutExpired:
                retry_count += 1
                if retry_count >= max_retries:
                    logging.error(f'Claude CLI timed out after {timeout} seconds (all retries exhausted)')
                    print(f"ERROR: Claude CLI timed out after {timeout} seconds. Try again later.")
                    return False
                logging.warning(f'Claude CLI timed out after {timeout} seconds, retrying ({retry_count}/{max_retries})')
                timeout *= backoff_factor  # Increase timeout for next attempt
            except subprocess.CalledProcessError as e:
                # Only retry on 5xx errors (server errors), not 4xx (client errors)
                if e.returncode >= 500 and e.returncode < 600 and retry_count < max_retries:
                    retry_count += 1
                    wait_time = backoff_factor ** retry_count
                    logging.warning(f'Claude CLI failed with server error {e.returncode}, retrying in {wait_time} seconds')
                    import time
                    time.sleep(wait_time)
                else:
                    logging.error(f'Claude CLI failed with error code {e.returncode}')
                    logging.error(f'Output: {e.output}')
                    logging.error(f'Error: {e.stderr}')
                    return False
            except FileNotFoundError:
                logging.error(f'Claude CLI not found at {CLAUDE_BIN}. Set the CLAUDE_BIN environment variable to the correct path.')
                print(f"ERROR: Claude CLI not found at {CLAUDE_BIN}")
                print("Set the CLAUDE_BIN environment variable to the correct path.")
                return False
        
        # Get organized playlist from Claude's response
        organized_playlist = result.stdout
        
        # Remove any empty lines and any introductory text from Claude
        organized_lines = []
        content_started = False
        
        for line in organized_playlist.split('\n'):
            # Skip empty lines
            if not line.strip():
                continue
                
            # If we see a line starting with '#', then we're in the content
            if line.strip().startswith('#'):
                content_started = True
                
            # Only add lines once we've reached actual content
            if content_started:
                organized_lines.append(line.strip())
        
        cleaned_playlist = '\n'.join(organized_lines)
        
        if dry_run:
            logging.info("Dry run - not writing changes to file")
            print(f"--- Organized Playlist (Dry Run) ---\n{cleaned_playlist}")
            return True
        
        # Write the organized playlist back to the file atomically
        atomic_write(playlist_file_path, cleaned_playlist)
        
        logging.debug('Playlist successfully organized by Claude')
        return True
        
    except Exception as e:
        import traceback
        logging.error(f'Error organizing playlist with Claude: {str(e)}')
        logging.error(f'Traceback: {traceback.format_exc()}')
        return False

def normalize_url(url):
    """
    Normalize URLs for more robust comparison, especially for YouTube links.
    """
    import urllib.parse
    
    try:
        parsed = urllib.parse.urlparse(url)
        
        # Handle YouTube URLs specifically
        if any(yt_domain in parsed.netloc for yt_domain in ['youtube.com', 'youtu.be', 'www.youtube.com']):
            query = urllib.parse.parse_qs(parsed.query)
            
            # Handle youtu.be format (video ID is in path)
            if 'youtu.be' in parsed.netloc:
                video_id = parsed.path.strip('/')
                return f"https://youtube.com/watch?v={video_id}"
            
            # Handle youtube.com format (video ID is in query)
            elif 'v' in query:
                video_id = query['v'][0]
                return f"https://youtube.com/watch?v={video_id}"
        
        # For non-YouTube URLs, just return the normalized form
        return url.lower().rstrip('/')
    except Exception as e:
        logging.warning(f"Error normalizing URL {url}: {e}")
        return url  # Return original URL if parsing fails

def append_to_playlist(url, description, playlist_file_path, dry_run=False):
    """
    Append a URL with description to a playlist file if it doesn't already exist.
    """
    logging.debug(f'Appending URL: {url} with description: {description} to playlist: {playlist_file_path}')
    
    # Format entry properly preserving any existing genre/mood/artist tag
    if ":" in description:
        # Check if it has a proper GENRE/MOOD [ARTIST] format or just GENRE format
        category_part = description.split(":", 1)[0].strip()
        if category_part.upper() == category_part:
            # Already has a proper format tag, use it as is
            entry = f"# {description}\n{url}\n"
        else:
            # Has a colon but not in the right format
            entry = f"# {description}\n{url}\n"
    else:
        # No genre tag, just add as is
        entry = f"# {description}\n{url}\n"
    
    path = pathlib.Path(playlist_file_path)
    existing_content = path.read_text() if path.exists() else ""
    
    # Normalize the URL for more robust duplicate checking
    normalized_url = normalize_url(url)
    
    # Check for duplicates (after normalization)
    is_duplicate = False
    for line in existing_content.splitlines():
        if line.startswith('http') and normalize_url(line.strip()) == normalized_url:
            is_duplicate = True
            break
    
    if not is_duplicate:
        if dry_run:
            logging.info("Dry run - not appending to file")
            print(f"Would append:\n{entry}")
            return True
            
        # If the file doesn't exist, create it and its parent directories
        path.parent.mkdir(parents=True, exist_ok=True)
        
        # Ensure the file ends with a newline before appending
        if existing_content and not existing_content.endswith('\n'):
            existing_content += '\n'
        
        # Append to the playlist file atomically
        new_content = existing_content + entry
        atomic_write(playlist_file_path, new_content)
        
        logging.debug('Entry appended successfully.')
        return True
    else:
        logging.debug(f'URL already exists in playlist (normalized: {normalized_url}).')
        return False

def create_prompt_template_file(custom_path=None):
    """
    Create a template prompt file at the specified path or default location if not exists.
    
    Args:
        custom_path: Optional path to save the template file at a different location
    """
    target_path = pathlib.Path(custom_path) if custom_path else PROMPT_FILE
    
    # Create parent directories if they don't exist
    target_path.parent.mkdir(parents=True, exist_ok=True)
    
    try:
        logging.info(f"Creating prompt template file at {target_path}")
        with open(target_path, 'w') as f:
            f.write(CLAUDE_PROMPT)
        print(f"Created prompt template file at {target_path}")
        print("You can customize this file to change the organization criteria and style.")
    except Exception as e:
        logging.error(f"Failed to create prompt template file: {e}")
        print(f"Failed to create prompt template file: {e}")

def cleanup_temp_files():
    """Clean up any stale temporary files from previous runs."""
    try:
        script_dir = pathlib.Path(__file__).parent
        for temp_file in script_dir.glob("*.tmp"):
            if temp_file.is_file():
                logging.info(f"Cleaning up stale temporary file: {temp_file}")
                temp_file.unlink()
    except Exception as e:
        logging.warning(f"Error cleaning up temporary files: {e}")

def signal_handler(signum, frame):
    """
    Handle interruption signals gracefully by cleaning up temporary files before exiting.
    """
    signal_name = "SIGINT" if signum == 2 else "SIGTERM" if signum == 15 else f"signal {signum}"
    logging.info(f"Received {signal_name}, cleaning up before exit...")
    cleanup_temp_files()
    print(f"\nProcess interrupted with {signal_name}, cleaned up temporary files.")
    sys.exit(1)

def main():
    """
    Main function with improved argument parsing and signal handling.
    """
    # Register signal handlers for graceful interruption
    import signal
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Clean up any stale temporary files from previous runs
    cleanup_temp_files()
    
    parser = argparse.ArgumentParser(
        description='''Playlist management tool for organizing music and video playlists.
        Uses Claude AI to categorize and organize entries by genre, mood, and artist.
        Supports dry run mode to preview changes without modifying files.''')
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Add command
    add_parser = subparsers.add_parser('add', help='Add a URL to the playlist')
    add_parser.add_argument('url', help='The URL to add')
    add_parser.add_argument('description', help='Description of the URL')
    add_parser.add_argument('playlist', help='Path to the playlist file')
    add_parser.add_argument('--dry-run', action='store_true', 
                           help='Show what would be done without making changes to the playlist file')
    add_parser.add_argument('--no-organize', action='store_true', help='Skip organizing the playlist after adding')
    
    # Reorganize command
    reorg_parser = subparsers.add_parser('reorg', help='Reorganize a playlist using Claude AI')
    reorg_parser.add_argument('playlist', help='Path to the playlist file')
    reorg_parser.add_argument('--dry-run', action='store_true', 
                             help='Preview Claude\'s organization without writing changes to the playlist file')
    
    # Export prompt template command
    export_parser = subparsers.add_parser('export-prompt', 
                                         help='Export the prompt template to a file for customization')
    export_parser.add_argument('--path', help='Custom path to save the template (defaults to playlist_prompt.md in script directory)')
    
    # Handle legacy command syntax
    if len(sys.argv) > 1 and sys.argv[1] == '--reorganize':
        # Convert legacy reorganize command to new format
        if len(sys.argv) < 3:
            parser.error('--reorganize requires a playlist file path')
        sys.argv = ['__append_to_playlist.py', 'reorg', sys.argv[2]]
    elif len(sys.argv) > 3 and sys.argv[1] != 'add' and sys.argv[1] != 'reorg' and sys.argv[1] != 'export-prompt':
        # Convert legacy add command to new format
        sys.argv = ['__append_to_playlist.py', 'add'] + sys.argv[1:4]
    
    args = parser.parse_args()
    
    # Default to help if no command provided
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # Handle export-prompt command
    if args.command == 'export-prompt':
        custom_path = getattr(args, 'path', None)
        create_prompt_template_file(custom_path)
        return
    
    # Expand user for playlist path
    if hasattr(args, 'playlist'):
        args.playlist = os.path.expanduser(args.playlist)
    
    success = True
    
    if args.command == 'add':
        entry_added = append_to_playlist(args.url, args.description, args.playlist, args.dry_run)
        
        # Organize the playlist after adding unless --no-organize is specified
        if not args.no_organize:
            success = organize_with_claude(args.playlist, args.dry_run)
    
    elif args.command == 'reorg':
        success = organize_with_claude(args.playlist, args.dry_run)
    
    logging.debug('Operation completed successfully.')
    
    # Proper exit code for script automation and CI/CD integration
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()

