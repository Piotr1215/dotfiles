#!/usr/bin/env python3
import googleapiclient.discovery
import os
import argparse
from prettytable import PrettyTable

# Replace with your API key and channel ID from environment variables
api_key = os.getenv('YOUTUBE_API_KEY')
channel_id = os.getenv('YOUTUBE_CHANNEL_ID')

# Initialize YouTube API
youtube = googleapiclient.discovery.build('youtube', 'v3', developerKey=api_key)

def get_all_video_data(channel_id):
    videos = []
    shorts = []
    next_page_token = None

    while True:
        # Fetch video titles in batches using pagination
        request = youtube.search().list(
            part='snippet',
            channelId=channel_id,
            maxResults=50,
            pageToken=next_page_token  # Handle pagination
        )
        response = request.execute()

        video_ids = []

        # Collect video IDs and titles
        for item in response['items']:
            if item['id']['kind'] == 'youtube#video':
                video_ids.append(item['id']['videoId'])

        # Fetch detailed information about each video
        video_request = youtube.videos().list(
            part="snippet,contentDetails,statistics",
            id=",".join(video_ids)
        )
        video_response = video_request.execute()

        for video in video_response['items']:
            title = video['snippet']['title']
            duration = video['contentDetails']['duration']
            views = int(video['statistics'].get('viewCount', '0'))  # Convert views to int
            likes = int(video['statistics'].get('likeCount', '0'))  # Convert likes to int

            # Shorts are under 60 seconds (PT1M or less)
            if 'PT1M' in duration or ('PT' in duration and 'M' not in duration):  # Shorts check
                shorts.append({
                    "title": title,
                    "views": views,
                    "likes": likes
                })
            else:
                videos.append({
                    "title": title,
                    "views": views,
                    "likes": likes
                })

        # Check if there's another page of results
        next_page_token = response.get('nextPageToken')

        if not next_page_token:
            break  # Exit the loop if no more pages

    return videos, shorts

def display_table(videos, shorts, show_shorts_stats):
    # Sort videos by views
    videos = sorted(videos, key=lambda x: x['views'], reverse=True)

    # Print videos with headers using PrettyTable
    video_table = PrettyTable()
    video_table.field_names = ["#", "Title", "Views", "Likes"]
    video_table.align["Title"] = "l"  # Left align the title

    for i, video in enumerate(videos, 1):
        video_table.add_row([i, video['title'], video['views'], video['likes']])

    print("Videos:")
    print(video_table)

    # Only print shorts if the --shorts flag is passed
    if show_shorts_stats:
        shorts = sorted(shorts, key=lambda x: x['views'], reverse=True)
        short_table = PrettyTable()
        short_table.field_names = ["#", "Title", "Views", "Likes"]
        short_table.align["Title"] = "l"  # Left align the title

        for i, short in enumerate(shorts, 1):
            short_table.add_row([i, short['title'], short['views'], short['likes']])

        print("\nShorts:")
        print(short_table)
    elif len(shorts) > 0:  # If the flag is not passed, show no shorts
        print("\nShorts are hidden (use --shorts flag to display them)")

# Argument parser to add --shorts flag
parser = argparse.ArgumentParser(description="Fetch YouTube video data")
parser.add_argument('--shorts', action='store_true', help='Include shorts statistics in the output')
args = parser.parse_args()

# Get videos and shorts with views and likes
videos, shorts = get_all_video_data(channel_id)

# Display the tables
display_table(videos, shorts, args.shorts)

# Summarize the results
total_videos = len(videos)
total_shorts = len(shorts)
total_content = total_videos + total_shorts

print("\nSummary:")
print(f"Total Videos: {total_videos}")
print(f"Total Shorts: {total_shorts}")
print(f"Total Content (Videos + Shorts): {total_content}")
