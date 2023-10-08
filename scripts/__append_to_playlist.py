#!/usr/bin/env python3
# This script is used to append a URL to a playlist file.
# Part of PROJECT:playlist
import json
import sys
import struct
import logging

logging.basicConfig(filename='/home/decoder/logme.log', level=logging.DEBUG)

def getMessage():
    rawLength = sys.stdin.buffer.read(4)
    if len(rawLength) == 0:
        sys.exit(0)
    messageLength = struct.unpack('@I', rawLength)[0]
    message = sys.stdin.buffer.read(messageLength).decode('utf-8')
    return json.loads(message)

def append_to_playlist(url, playlist_file_path):
    logging.debug(f'Appending URL: {url} to playlist: {playlist_file_path}')
    with open(playlist_file_path, 'r') as f:
        existing_urls = f.readlines()

    existing_urls = [line.strip() for line in existing_urls]

    if url not in existing_urls:
        with open(playlist_file_path, 'a') as f:
            f.write(url + '\n')
        logging.debug(f'URL: {url} appended successfully.')
    else:
        logging.debug(f'URL: {url} already exists in playlist.')

def main():
    logging.debug('Script started')
    receivedMessage = getMessage()
    url = receivedMessage.get("url")
    
    if url:
        playlist_file_path = "/home/decoder/haruna_playlist.m3u"
        append_to_playlist(url, playlist_file_path)
        logging.debug('Success response sent.')
    else:
        logging.debug('Error response sent due to missing URL.')

if __name__ == "__main__":
    main()
