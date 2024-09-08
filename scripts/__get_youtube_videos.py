#!/usr/bin/env python3
import googleapiclient.discovery
import os

# Replace with your API key and channel ID from environment variables
api_key = os.getenv('YOUTUBE_API_KEY')
channel_id = os.getenv('YOUTUBE_CHANNEL_ID')

# Initialize YouTube API
youtube = googleapiclient.discovery.build('youtube', 'v3', developerKey=api_key)

def get_all_video_titles_and_shorts(channel_id):
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
            part="snippet,contentDetails",
            id=",".join(video_ids)
        )
        video_response = video_request.execute()

        for video in video_response['items']:
            title = video['snippet']['title']
            duration = video['contentDetails']['duration']

            # Shorts are under 60 seconds (PT1M or less)
            if 'PT1M' in duration or ('PT' in duration and 'M' not in duration):  # Shorts check
                shorts.append(title)
            else:
                videos.append(title)

        # Check if there's another page of results
        next_page_token = response.get('nextPageToken')

        if not next_page_token:
            break  # Exit the loop if no more pages

    return videos, shorts

# Get videos and shorts separately
videos, shorts = get_all_video_titles_and_shorts(channel_id)

# Print videos with count numbers
print("Videos:")
for i, video in enumerate(videos, 1):
    print(f"{i}. {video}")

print("\nShorts:")
for i, short in enumerate(shorts, 1):
    print(f"{i}. {short}")

# Summarize the results
total_videos = len(videos)
total_shorts = len(shorts)
total_content = total_videos + total_shorts

print("\nSummary:")
print(f"Total Videos: {total_videos}")
print(f"Total Shorts: {total_shorts}")
print(f"Total Content (Videos + Shorts): {total_content}")
