import os
import subprocess

# PROJECT: music-download
# Downloads YouTube audio as MP3 to ~/music/ for local playback
music_folder_path = os.path.expanduser('~/music')
download_script_path = '/home/decoder/dev/dotfiles/scripts/__download_youtube.sh'
autoclose_zenity_script = '/home/decoder/dev/dotfiles/scripts/__auto_close_zenity.sh'

def download_music():
    url = clipboard.get_clipboard()

    if not url or 'youtu' not in url:
        subprocess.run([autoclose_zenity_script, "No YouTube URL in clipboard"])
        return

    # Get the video title first to check if already downloaded
    video_title = subprocess.getoutput(f"yt-dlp --get-filename -o '%(title)s' --restrict-filenames --no-playlist '{url}'")
    expected_file = os.path.join(music_folder_path, f"{video_title}.mp3")

    if os.path.exists(expected_file):
        subprocess.run([autoclose_zenity_script, f"Already exists: {video_title}"])
        return

    # Download as MP3 (runs in background)
    subprocess.Popen([download_script_path, '-mp3', url])
    subprocess.run([autoclose_zenity_script, f"Downloading: {video_title}"])

# Get the active window title
active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")

# Check if the active window is a browser
if 'Firefox' in active_window_title or 'LibreWolf' in active_window_title:
    download_music()
    clipboard.fill_clipboard("")
    clipboard.fill_selection("")
