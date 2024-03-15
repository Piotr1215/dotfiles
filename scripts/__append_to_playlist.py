#!/usr/bin/env python3
import sys
import logging
import os

logging.basicConfig(filename=os.path.expanduser('/home/decoder/logme.log'), level=logging.DEBUG)

def append_to_playlist(url, description, playlist_file_path):
    logging.debug(f'Appending URL: {url} with description: {description} to playlist: {playlist_file_path}')
    entry = f"# {description}\n{url}\n"
    with open(playlist_file_path, 'r') as f:
        existing_content = f.read()

    if url not in existing_content:
        with open(playlist_file_path, 'a') as f:
            f.write(entry)
        logging.debug('Entry appended successfully.')
    else:
        logging.debug('URL already exists in playlist.')

def main():
    if len(sys.argv) < 4:
        logging.error('Usage: __append_to_playlist.py <url> <description> <playlist_file_path>')
        sys.exit(1)

    url = sys.argv[1]
    description = sys.argv[2]
    playlist_file_path = os.path.expanduser(sys.argv[3])

    append_to_playlist(url, description, playlist_file_path)
    logging.debug('Success response sent.')

if __name__ == "__main__":
    main()

