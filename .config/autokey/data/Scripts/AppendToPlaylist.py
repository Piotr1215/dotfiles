import os
import subprocess

# PROJECT: playlist
vids_playlist_path = os.path.expanduser('~/vids_playlist.m3u')
# Path to the Videos folder
videos_folder_path = os.path.expanduser('~/Videos')
# Path to the Bash script for downloading YouTube videos
download_script_path = '/home/decoder/dev/dotfiles/scripts/__download_youtube.sh'
autoclose_zenity_script = '/home/decoder/dev/dotfiles/scripts/__auto_close_zenity.sh'

def append_to_playlist(playlist_file_path):
    url = clipboard.get_clipboard()

    # Read existing URLs from the playlist file
    existing_urls = []
    if os.path.exists(playlist_file_path):
        with open(playlist_file_path, 'r') as f:
            existing_urls = [line.strip() for line in f.readlines()]

    # Check if the URL is already in the playlist
    if url not in existing_urls:
        # Call the Bash script to download the video
        subprocess.run([autoclose_zenity_script, f"Downloading: {url}"])
        subprocess.run([download_script_path])

        # Get the video title
        video_title = subprocess.getoutput(f"yt-dlp --get-filename -o '%(title)s' --no-playlist {url}")

        # Generate the video file path
        video_file_path = os.path.join(videos_folder_path, f"{video_title}.webm")

        # Append the video file path to the playlist file
        with open(playlist_file_path, 'a') as f:
            f.write(video_file_path + '\n')
        # Show Zenity notification
        subprocess.run([autoclose_zenity_script, f"Downloaded: {video_title}"])

# Get the active window title
active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")

# Check if the active window is Firefox
if 'Firefox' in active_window_title:
    append_to_playlist(vids_playlist_path)
    
    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
