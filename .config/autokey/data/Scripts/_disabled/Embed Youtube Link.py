import subprocess
import re

def extract_youtube_id(url):
    patterns = [
        r'(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\n?]+)',
        r'youtube\.com\/shorts\/([^&\n?]+)'
    ]
    
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None

active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")
if 'Firefox' in active_window_title or 'Chrome' in active_window_title or 'Brave' in active_window_title or 'LibreWolf' in active_window_title:
    clipboard.fill_clipboard("")  
    keyboard.send_keys('yy')
    time.sleep(0.5)
    url = clipboard.get_clipboard()
    
    # Extract video ID and create embedded link
    video_id = extract_youtube_id(url)
    if video_id:
        thumbnail_url = f"https://img.youtube.com/vi/{video_id}/0.jpg"
        video_url = f"https://www.youtube.com/watch?v={video_id}"
        combined = f"[![Video Thumbnail]({thumbnail_url})]({video_url})"
        clipboard.fill_clipboard(combined)
    else:
        # Fallback to regular markdown link if not a YouTube URL
        combined = f"[{url}]({url})"
        clipboard.fill_clipboard(combined)