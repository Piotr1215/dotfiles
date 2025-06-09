#!/usr/bin/env python3
import googleapiclient.discovery
import os
import argparse
from prettytable import PrettyTable
from datetime import datetime

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
            published_at = video['snippet']['publishedAt'][:10]  # Extract date only (YYYY-MM-DD)

            # Shorts are under 60 seconds (PT1M or less)
            if 'PT1M' in duration or ('PT' in duration and 'M' not in duration):  # Shorts check
                shorts.append({
                    "title": title,
                    "views": views,
                    "likes": likes,
                    "published_at": published_at
                })
            else:
                videos.append({
                    "title": title,
                    "views": views,
                    "likes": likes,
                    "published_at": published_at
                })

        # Check if there's another page of results
        next_page_token = response.get('nextPageToken')

        if not next_page_token:
            break  # Exit the loop if no more pages

    return videos, shorts

def display_table(videos, shorts, show_shorts_stats, sort_by_date):
    # Sort videos by views or date
    if sort_by_date:
        videos = sorted(videos, key=lambda x: x['published_at'], reverse=True)
        # Calculate days between consecutive videos
        if videos:
            for i, video in enumerate(videos):
                if i == len(videos) - 1:
                    video['days_since_last'] = '-'  # No previous video for the oldest one
                else:
                    current_date = datetime.strptime(video['published_at'], '%Y-%m-%d')
                    next_date = datetime.strptime(videos[i+1]['published_at'], '%Y-%m-%d')
                    days_diff = (current_date - next_date).days
                    video['days_since_last'] = days_diff
    else:
        videos = sorted(videos, key=lambda x: x['views'], reverse=True)

    # Print videos with headers using PrettyTable
    video_table = PrettyTable()
    if sort_by_date:
        video_table.field_names = ["#", "Title", "Views", "Likes", "Published", "Gap (days)"]
    else:
        video_table.field_names = ["#", "Title", "Views", "Likes", "Published"]
    video_table.align["Title"] = "l"  # Left align the title

    for i, video in enumerate(videos, 1):
        if sort_by_date:
            video_table.add_row([i, video['title'], video['views'], video['likes'], video['published_at'], video['days_since_last']])
        else:
            video_table.add_row([i, video['title'], video['views'], video['likes'], video['published_at']])

    print("Videos:")
    print(video_table)

    # Only print shorts if the --shorts flag is passed
    if show_shorts_stats:
        if sort_by_date:
            shorts = sorted(shorts, key=lambda x: x['published_at'], reverse=True)
            # Calculate days between consecutive shorts
            if shorts:
                for i, short in enumerate(shorts):
                    if i == len(shorts) - 1:
                        short['days_since_last'] = '-'  # No previous short for the oldest one
                    else:
                        current_date = datetime.strptime(short['published_at'], '%Y-%m-%d')
                        next_date = datetime.strptime(shorts[i+1]['published_at'], '%Y-%m-%d')
                        days_diff = (current_date - next_date).days
                        short['days_since_last'] = days_diff
        else:
            shorts = sorted(shorts, key=lambda x: x['views'], reverse=True)
        
        short_table = PrettyTable()
        if sort_by_date:
            short_table.field_names = ["#", "Title", "Views", "Likes", "Published", "Gap (days)"]
        else:
            short_table.field_names = ["#", "Title", "Views", "Likes", "Published"]
        short_table.align["Title"] = "l"  # Left align the title

        for i, short in enumerate(shorts, 1):
            if sort_by_date:
                short_table.add_row([i, short['title'], short['views'], short['likes'], short['published_at'], short['days_since_last']])
            else:
                short_table.add_row([i, short['title'], short['views'], short['likes'], short['published_at']])

        print("\nShorts:")
        print(short_table)
    elif len(shorts) > 0:  # If the flag is not passed, show no shorts
        print("\nShorts are hidden (use --shorts flag to display them)")

# Argument parser to add --shorts and --date flags
parser = argparse.ArgumentParser(description="Fetch YouTube video data")
parser.add_argument('--shorts', action='store_true', help='Include shorts statistics in the output')
parser.add_argument('--date', action='store_true', help='Sort by publication date instead of views')
args = parser.parse_args()

# Get videos and shorts with views and likes
videos, shorts = get_all_video_data(channel_id)

# Display the tables
display_table(videos, shorts, args.shorts, args.date)

# Summarize the results
total_videos = len(videos)
total_shorts = len(shorts)
total_content = total_videos + total_shorts

print("\nSummary:")
print(f"Total Videos: {total_videos}")
print(f"Total Shorts: {total_shorts}")
print(f"Total Content (Videos + Shorts): {total_content}")
