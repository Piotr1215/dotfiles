#!/usr/bin/env python3
"""
This script converts text from an input file into speech and saves it as an MP3 file.
Usage: voicer.py <input_file>
    <input_file>: Path to the text file to be converted to speech.
The script uses the OpenAI API to perform the text-to-speech conversion.
"""
import sys
from openai import OpenAI

if len(sys.argv) != 2:
    print("Usage: voicer.py <input_file>")
    sys.exit(1)

input_file = sys.argv[1]

with open(input_file, 'r') as file:
    input_text = file.read()

client = OpenAI()

with client.audio.speech.with_streaming_response.create(
    model="tts-1",
    voice="alloy",
    input=input_text,
) as response:
    response.stream_to_file("/tmp/speech.mp3")

print("Speech saved to /tmp/speech.mp3")
