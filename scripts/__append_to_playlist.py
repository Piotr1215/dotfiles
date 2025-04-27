#!/usr/bin/env python3
import argparse
import logging
import os
import subprocess
import tempfile
import time
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

def check_claude_cli():
    """
    Check if the Claude CLI is installed and working correctly.
    Returns a tuple of (success, message)
    """
    try:
        # Check if the binary exists and is executable
        if not os.path.exists(CLAUDE_BIN):
            return False, f"Claude CLI not found at: {CLAUDE_BIN}"
        
        # Check version to ensure it's working
        result = subprocess.run(
            [CLAUDE_BIN, "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return False, f"Claude CLI returned error code: {result.returncode}"
        
        # Successfully retrieved version
        return True, f"Claude CLI {result.stdout.strip()} is ready"
    except Exception as e:
        return False, f"Error checking Claude CLI: {str(e)}"

def auto_tag_entry(title, _):
    """
    Automatically tag an entry based on keywords in the title.
    This is a fallback when Claude isn't available or times out.
    
    Args:
        title: The title to tag
        _: Unused parameter (kept for API compatibility)
        
    Returns:
        A formatted title with genre/mood tags
    """
    title_lower = title.lower()
    
    # Define keyword mappings
    keywords = {
        'ambient': {
            'calm': ['calm', 'peaceful', 'gentle', 'relaxing', 'meditation'],
            'dark': ['dark', 'horror', 'lovecraft', 'mysterious', 'enigmatic', 'eerie'],
            'dreamy': ['dream', 'dreamy', 'sleep', 'ethereal'],
            'nature': ['nature', 'forest', 'rain', 'ocean', 'sea', 'wind', 'birds'],
            'ethereal': ['ethereal', 'spacey', 'space', 'cosmic', 'universe']
        },
        'lofi': {
            'chill': ['chill', 'relax', 'peace', 'study'],
            'jazz': ['jazz'],
            'hiphop': ['hip hop', 'hip-hop', 'hiphop', 'beats']
        },
        'electronic': {
            'upbeat': ['upbeat', 'dance', 'edm', 'party'],
            'chill': ['chill', 'downtempo'],
            'experimental': ['experimental', 'glitch', 'idm']
        },
        'classical': {
            'piano': ['piano', 'chopin', 'liszt', 'beethoven', 'mozart'],
            'orchestral': ['orchestra', 'symphony', 'classical'],
            'focus': ['focus', 'study', 'concentration', 'work']
        },
        'focus': {
            'deep': ['deep focus', 'deep work', 'concentration'],
            'light': ['light', 'easy', 'background'],
            'coding': ['code', 'coding', 'programming', 'developer']
        },
        'instrumental': {
            'piano': ['piano', 'keys'],
            'guitar': ['guitar', 'acoustic'],
            'orchestral': ['orchestra', 'strings', 'ensemble']
        },
        'soundtrack': {
            'ambient': ['ambient', 'atmospheric', 'environment'],
            'cinematic': ['cinematic', 'epic', 'movie', 'film'],
            'mystery': ['mystery', 'detective', 'noir']
        },
        'techno': {
            'cyberpunk': ['cyberpunk', 'cyber', 'futuristic', 'blade runner'],
            'dark': ['dark', 'industrial', 'heavy', 'bass'],
            'experimental': ['experimental', 'abstract', 'minimal']
        }
    }
    
    # Find the best match based on keywords
    best_genre = 'AMBIENT'  # Default if no matches found
    best_mood = 'CALM'      # Default if no matches found
    max_matches = 0
    
    for genre, moods in keywords.items():
        for mood, mood_keywords in moods.items():
            matches = sum(1 for keyword in mood_keywords if keyword in title_lower)
            if matches > max_matches:
                max_matches = matches
                best_genre = genre
                best_mood = mood
                
    # Ensure we always have valid values by using the defaults if nothing matched
    assert best_genre is not None, "Genre should never be None"
    assert best_mood is not None, "Mood should never be None"
    
    # Extract potential artist if it's in brackets or parentheses
    artist = ""
    if '[' in title and ']' in title:
        start = title.find('[') + 1
        end = title.find(']', start)
        if start < end:  # Ensure valid range
            artist = title[start:end]
    elif '(' in title and ')' in title:
        start = title.find('(') + 1
        end = title.find(')', start)
        if start < end:  # Ensure valid range
            artist = title[start:end]
    
    # If artist found, include it, otherwise just use the genre/mood
    genre_mood_tag = f"{best_genre.upper()}/{best_mood.upper()}"
    if artist and len(artist) > 0 and len(artist) < 30:  # Avoid using very long text in parentheses
        artist_tag = f"[{artist.upper()}]"
        return f"# {genre_mood_tag} {artist_tag}: {title}"
    else:
        return f"# {genre_mood_tag}: {title}"

def tag_entry_with_claude(title, url):
    """
    Use Claude to tag a single playlist entry with proper genre/mood and artist information.
    Falls back to auto-tagging if Claude times out or fails.
    
    Args:
        title: The title or description of the entry
        url: The URL of the entry
        
    Returns:
        Properly formatted title with genre/mood and artist tags
    """
    logging.debug(f'Asking Claude to tag entry: {title}')
    
    # Check if Claude CLI is working
    claude_ok, message = check_claude_cli()
    if not claude_ok:
        logging.warning(f"Claude not available: {message}")
        return auto_tag_entry(title, url)
    
    # Prompt focused specifically on tagging one audio entry
    prompt = f"""
You're a music categorizer that adds genre tags to a single track.

Title: {title}

Task: Format this single title with the pattern: # GENRE/MOOD [ARTIST]: Title

Available categories (use EXACTLY as shown with the slash):
- AMBIENT/CALM, AMBIENT/DARK, AMBIENT/DREAMY, AMBIENT/ETHEREAL, AMBIENT/NATURE
- ELECTRONIC/UPBEAT, ELECTRONIC/CHILL, ELECTRONIC/EXPERIMENTAL
- FOCUS/DEEP, FOCUS/LIGHT, FOCUS/CODING
- INSTRUMENTAL/PIANO, INSTRUMENTAL/GUITAR, INSTRUMENTAL/ORCHESTRAL
- LOFI/JAZZ, LOFI/HIPHOP, LOFI/CHILL
- SOUNDTRACK/AMBIENT, SOUNDTRACK/EPIC, SOUNDTRACK/CINEMATIC
- CLASSICAL/PIANO, CLASSICAL/ORCHESTRAL, CLASSICAL/FOCUS
- TECHNO/CYBERPUNK, TECHNO/DARK, TECHNO/EXPERIMENTAL
- TUTORIAL/DEV, TALK/TECH, TALK/PHILOSOPHY

Rules:
1. Format MUST be: # GENRE/MOOD [ARTIST]: Title
2. Always use ALL CAPS for GENRE/MOOD and [ARTIST]
3. If no artist is identifiable, omit [ARTIST] part
4. Keep existing star emoji (⭐) if present
5. Reply ONLY with the formatted line, nothing else

Examples:
For "Dark ambient drones" → # AMBIENT/DARK: Dark ambient drones
For "Chopin Nocturne" → # CLASSICAL/PIANO [CHOPIN]: Chopin Nocturne
For "⭐ Coding beats" → # FOCUS/CODING: ⭐ Coding beats
"""
    
    # Call Claude CLI with a longer timeout
    try:
        start_time = time.time()
        result = subprocess.run(
            [CLAUDE_BIN, '-p', prompt],
            capture_output=True,
            text=True,
            check=True,
            timeout=30  # Longer timeout to account for Claude CLI
        )
        elapsed_time = time.time() - start_time
        logging.debug(f'Claude responded in {elapsed_time:.2f} seconds')
        
        # Get Claude's response and clean it up
        tagged_title = result.stdout.strip()
        
        # If Claude returned nothing useful, use auto-tagging
        if not tagged_title:
            logging.warning(f"Claude returned empty response for '{title}', using auto-tagging")
            return auto_tag_entry(title, url)
            
        # Make sure the result starts with # for a properly formatted title
        if tagged_title.startswith('#'):
            return tagged_title
        elif tagged_title.startswith('# '):
            return tagged_title
        else:
            # Fix issues where Claude might not return with the # prefix
            return f"# {tagged_title}"
            
    except subprocess.TimeoutExpired:
        logging.warning(f"Claude timed out while tagging '{title}', using auto-tagging")
        return auto_tag_entry(title, url)
    except Exception as e:
        logging.error(f'Error tagging entry with Claude: {str(e)}')
        return auto_tag_entry(title, url)
        
def organize_playlist(playlist_file_path, dry_run=False):
    """
    Reorganize a playlist file using Python code for sorting and structure.
    Only uses Claude for tagging new entries that aren't properly formatted yet.
    """
    logging.debug(f'Organizing playlist: {playlist_file_path}')
    
    try:
        # Read the playlist content
        playlist_content = pathlib.Path(playlist_file_path).read_text()
        
        # Parse the playlist into entries (title and URL pairs)
        entries = []
        lines = playlist_content.strip().split('\n')
        
        i = 0
        while i < len(lines):
            if lines[i].strip().startswith('#'):
                title = lines[i].strip()
                url = lines[i+1].strip() if i+1 < len(lines) else ""
                
                # Check if the title is properly formatted (has GENRE/MOOD tag)
                title_upper = title.upper()
                if not any(category in title_upper for category in ['AMBIENT/', 'ELECTRONIC/', 'FOCUS/', 'LOFI/', 'INSTRUMENTAL/', 'SOUNDTRACK/', 'CLASSICAL/', 'TUTORIAL/', 'TALK/', 'TECHNO/']):
                    logging.debug(f"Found untagged entry: {title}")
                    # Title is not properly formatted, get proper tagging from Claude
                    title = tag_entry_with_claude(title.replace('#', '').strip(), url)
                
                entries.append((title, url))
                i += 2
            else:
                # Skip malformed lines
                i += 1
        
        # Function to extract genre/mood and artist for sorting
        def get_sort_keys(entry):
            title = entry[0]
            
            # Skip the initial # if present for parsing
            if title.startswith('# '):
                title = title[2:]
            elif title.startswith('#'):
                title = title[1:]
                
            # Extract genre/mood
            genre_mood = ""
            if ':' in title and '/' in title:
                parts = title.split(':', 1)[0].strip()
                genre_mood = parts.split('[')[0].strip() if '[' in parts else parts.strip()
            
            # Extract artist if present
            artist = ""
            if '[' in title and ']' in title:
                artist = title.split('[', 1)[1].split(']', 1)[0]
            
            return (genre_mood, artist, title)
        
        # Sort entries by genre/mood then artist
        entries.sort(key=get_sort_keys)
        
        # Build the organized playlist
        organized_content = []
        for title, url in entries:
            organized_content.append(title)
            organized_content.append(url)
        
        organized_playlist = '\n'.join(organized_content)
        
        if dry_run:
            logging.info("Dry run - not writing changes to file")
            print(f"--- Organized Playlist (Dry Run) ---\n{organized_playlist}")
            return True
        
        # Write the organized playlist back to the file atomically
        atomic_write(playlist_file_path, organized_playlist)
        
        logging.debug('Playlist successfully organized')
        return True
        
    except Exception as e:
        import traceback
        logging.error(f'Error organizing playlist: {str(e)}')
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

def signal_handler(signum, _):
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
        # Add the URL to the playlist
        success = append_to_playlist(args.url, args.description, args.playlist, args.dry_run)
        
        # Organize the playlist after adding unless --no-organize is specified
        if success and not args.no_organize:
            success = organize_playlist(args.playlist, args.dry_run)
    
    elif args.command == 'reorg':
        success = organize_playlist(args.playlist, args.dry_run)
    
    logging.debug('Operation completed successfully.')
    
    # Proper exit code for script automation and CI/CD integration
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()

