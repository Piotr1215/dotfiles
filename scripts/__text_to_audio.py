#!/usr/bin/env python3
import os
import sys
import re
from gtts import gTTS
import argparse

def read_file(filepath):
    with open(filepath, 'r') as file:
        content = file.read()

    if filepath.endswith('.md'):
        content = re.sub(r'```.*?```', ' code ', content, flags=re.DOTALL)  # Remove code blocks
        content = re.sub(r'#{1,6}', '', content)  # Remove markdown headings
        content = re.sub(r'\`.*?\`', ' code ', content)  # Remove inline code

    content = re.sub(r'https?://\S+', ' link ', content)  # Replace URLs with "link"
    return content

def main():
    parser = argparse.ArgumentParser(description='Text-to-speech script')
    parser.add_argument('--save', action='store_true', help='Save audio to file instead of playing')
    args = parser.parse_args()

    filepath = None

    if os.path.exists('input.txt'):
        filepath = 'input.txt'
    elif os.path.exists('input.md'):
        filepath = 'input.md'
    else:
        filepath = input('Please provide the path to your input file (txt or md): ')

    content = read_file(filepath)
    tts = gTTS(content, lang='en', slow=False)

    if args.save:
        output_filename = filepath[:-4] + '_audio.mp3'
        tts.save(output_filename)
        print(f'Audio saved to {output_filename}')
    else:
        tts.save('temp_audio.mp3')
        os.system('mpg123 -q temp_audio.mp3')
        os.remove('temp_audio.mp3')

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('Interrupted by user. Exiting.')
        sys.exit(0)
