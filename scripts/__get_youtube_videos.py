#!/usr/bin/env python3
import googleapiclient.discovery
import os
import argparse
from prettytable import PrettyTable
from datetime import datetime
import html

# Replace with your API key and channel ID from environment variables
api_key = os.getenv('YOUTUBE_API_KEY')
channel_id = os.getenv('YOUTUBE_CHANNEL_ID')

# Initialize YouTube API
youtube = googleapiclient.discovery.build('youtube', 'v3', developerKey=api_key)

def get_video_comments(video_id, max_results=100):
    comments = []
    next_page_token = None
    
    try:
        while len(comments) < max_results:
            request = youtube.commentThreads().list(
                part="snippet,replies",
                videoId=video_id,
                maxResults=min(100, max_results - len(comments)),
                pageToken=next_page_token,
                order="relevance"
            )
            response = request.execute()
            
            for item in response.get('items', []):
                # Top level comment
                top_comment = item['snippet']['topLevelComment']['snippet']
                comment_data = {
                    'text': html.unescape(top_comment['textDisplay']),
                    'author': html.unescape(top_comment['authorDisplayName']),
                    'likes': top_comment['likeCount'],
                    'replies': []
                }
                
                # Get replies if they exist
                if item['snippet']['totalReplyCount'] > 0 and 'replies' in item:
                    for reply in item['replies']['comments']:
                        reply_snippet = reply['snippet']
                        comment_data['replies'].append({
                            'text': html.unescape(reply_snippet['textDisplay']),
                            'author': html.unescape(reply_snippet['authorDisplayName']),
                            'likes': reply_snippet['likeCount']
                        })
                
                comments.append(comment_data)
            
            next_page_token = response.get('nextPageToken')
            if not next_page_token:
                break
                
    except Exception as e:
        print(f"Error fetching comments: {e}")
    
    return comments

def get_all_video_data(channel_id, fetch_comments=False):
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
            video_id = video['id']
            title = video['snippet']['title']
            duration = video['contentDetails']['duration']
            views = int(video['statistics'].get('viewCount', '0'))  # Convert views to int
            likes = int(video['statistics'].get('likeCount', '0'))  # Convert likes to int
            published_at = video['snippet']['publishedAt'][:10]  # Extract date only (YYYY-MM-DD)
            
            video_data = {
                "id": video_id,
                "title": title,
                "views": views,
                "likes": likes,
                "published_at": published_at
            }
            
            # Fetch comments if requested
            if fetch_comments:
                video_data["comments"] = get_video_comments(video_id)

            # Shorts are under 60 seconds (PT1M or less)
            if 'PT1M' in duration or ('PT' in duration and 'M' not in duration):  # Shorts check
                shorts.append(video_data)
            else:
                videos.append(video_data)

        # Check if there's another page of results
        next_page_token = response.get('nextPageToken')

        if not next_page_token:
            break  # Exit the loop if no more pages

    return videos, shorts

def display_table(videos, shorts, show_shorts_stats, sort_by_date, show_comments):
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
    
    # Display comments if requested
    if show_comments:
        print("\n" + "="*80)
        for i, video in enumerate(videos, 1):
            if 'comments' in video and video['comments']:
                print(f"\n[{i}] {video['title']}")
                print("Comments:")
                for comment in video['comments'][:10]:  # Show top 10 comments
                    print(f"\n- {comment['author']} ({comment['likes']} likes):")
                    print(f"  {comment['text'][:200]}..." if len(comment['text']) > 200 else f"  {comment['text']}")
                    
                    # Show replies
                    for reply in comment['replies'][:3]:  # Show up to 3 replies
                        print(f"  -- {reply['author']} ({reply['likes']} likes):")
                        print(f"     {reply['text'][:150]}..." if len(reply['text']) > 150 else f"     {reply['text']}")
                    
                    if len(comment['replies']) > 3:
                        print(f"  -- ... and {len(comment['replies']) - 3} more replies")
                print("\n" + "-"*80)

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
        
        # Display comments for shorts if requested
        if show_comments:
            print("\n" + "="*80)
            for i, short in enumerate(shorts, 1):
                if 'comments' in short and short['comments']:
                    print(f"\n[{i}] {short['title']}")
                    print("Comments:")
                    for comment in short['comments'][:5]:  # Show top 5 comments for shorts
                        print(f"\n- {comment['author']} ({comment['likes']} likes):")
                        print(f"  {comment['text'][:200]}..." if len(comment['text']) > 200 else f"  {comment['text']}")
                        
                        # Show replies
                        for reply in comment['replies'][:2]:  # Show up to 2 replies for shorts
                            print(f"  -- {reply['author']} ({reply['likes']} likes):")
                            print(f"     {reply['text'][:150]}..." if len(reply['text']) > 150 else f"     {reply['text']}")
                        
                        if len(comment['replies']) > 2:
                            print(f"  -- ... and {len(comment['replies']) - 2} more replies")
                    print("\n" + "-"*80)
    elif len(shorts) > 0:  # If the flag is not passed, show no shorts
        print("\nShorts are hidden (use --shorts flag to display them)")

# Argument parser to add --shorts, --date, and --comments flags
parser = argparse.ArgumentParser(description="Fetch YouTube video data")
parser.add_argument('--shorts', action='store_true', help='Include shorts statistics in the output')
parser.add_argument('--date', action='store_true', help='Sort by publication date instead of views')
parser.add_argument('--comments', action='store_true', help='Fetch and display comments for videos')
args = parser.parse_args()

# Get videos and shorts with views and likes
print("Fetching video data..." + (" (this may take longer with comments)" if args.comments else ""))
videos, shorts = get_all_video_data(channel_id, fetch_comments=args.comments)

# Display the tables
display_table(videos, shorts, args.shorts, args.date, args.comments)

# Summarize the results
total_videos = len(videos)
total_shorts = len(shorts)
total_content = total_videos + total_shorts

print("\nSummary:")
print(f"Total Videos: {total_videos}")
print(f"Total Shorts: {total_shorts}")
print(f"Total Content (Videos + Shorts): {total_content}")
