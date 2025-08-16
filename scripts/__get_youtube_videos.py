#!/usr/bin/env python3
import googleapiclient.discovery
import os
import argparse
from prettytable import PrettyTable
from datetime import datetime
import html
import subprocess
import json
import sys

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
    seen_ids = set()  # Track video IDs to prevent duplicates
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
                video_id = item['id']['videoId']
                if video_id not in seen_ids:  # Only add if not seen before
                    video_ids.append(video_id)
                    seen_ids.add(video_id)

        # Fetch detailed information about each video
        if video_ids:  # Only make request if we have new videos
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

def format_video_for_fzf(video):
    """Format video data for fzf selection"""
    # Truncate title if too long and add ellipsis
    title = video['title']
    if len(title) > 57:
        title = title[:57] + "..."
    return f"{title:<60} | {video['views']:>10,} views | {video['likes']:>7,} likes | {video['published_at']}"

def display_video_details(video):
    """Display detailed information about a selected video"""
    print(f"\n{'='*80}")
    print(f"Title: {video['title']}")
    print(f"Video ID: {video['id']}")
    print(f"URL: https://www.youtube.com/watch?v={video['id']}")
    print(f"Published: {video['published_at']}")
    print(f"Views: {video['views']:,}")
    print(f"Likes: {video['likes']:,}")
    
    if 'comments' in video and video['comments']:
        print(f"\nTop Comments ({len(video['comments'])} total):")
        print("-"*40)
        for i, comment in enumerate(video['comments'][:5], 1):
            print(f"\n[{i}] {comment['author']} ({comment['likes']} likes):")
            print(f"    {comment['text'][:300]}..." if len(comment['text']) > 300 else f"    {comment['text']}")
            
            if comment['replies']:
                print(f"    └─ {len(comment['replies'])} replies")
                for reply in comment['replies'][:2]:
                    print(f"       • {reply['author']}: {reply['text'][:150]}..." if len(reply['text']) > 150 else f"       • {reply['author']}: {reply['text']}")
    
    print(f"{'='*80}\n")

def interactive_fzf_selection(videos, shorts, show_shorts):
    """Use fzf to interactively select a video and display its details"""
    # Combine videos and shorts if requested
    all_content = videos.copy()
    if show_shorts:
        # Add marker to distinguish shorts
        for short in shorts:
            short['_is_short'] = True
        all_content.extend(shorts)
    
    # Function to create sorted fzf input
    def create_sorted_input(content, sort_key):
        if sort_key == 'date':
            sorted_content = sorted(content, key=lambda x: x['published_at'], reverse=True)
        elif sort_key == 'views':
            sorted_content = sorted(content, key=lambda x: x['views'], reverse=True)
        elif sort_key == 'likes':
            sorted_content = sorted(content, key=lambda x: x['likes'], reverse=True)
        elif sort_key == 'name':
            sorted_content = sorted(content, key=lambda x: x['title'].lower())
        else:
            sorted_content = content
        
        lines = []
        for item in sorted_content:
            prefix = "[SHORT] " if item.get('_is_short') else ""
            lines.append(f"{prefix}{format_video_for_fzf(item)}")
        return '\n'.join(lines), sorted_content
    
    # Create initial sorted input (default by date)
    initial_input, sorted_content = create_sorted_input(all_content, 'date')
    
    # Create temporary files for different sorts
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='_date.txt', delete=False) as f_date:
        date_input, _ = create_sorted_input(all_content, 'date')
        f_date.write(date_input)
        date_file = f_date.name
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='_views.txt', delete=False) as f_views:
        views_input, _ = create_sorted_input(all_content, 'views')
        f_views.write(views_input)
        views_file = f_views.name
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='_likes.txt', delete=False) as f_likes:
        likes_input, _ = create_sorted_input(all_content, 'likes')
        f_likes.write(likes_input)
        likes_file = f_likes.name
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='_name.txt', delete=False) as f_name:
        name_input, _ = create_sorted_input(all_content, 'name')
        f_name.write(name_input)
        name_file = f_name.name
    
    # Run fzf
    try:
        fzf_cmd = [
            'fzf',
            '--prompt', '> Select video (date): ',
            '--header', 'ctrl-o: date | ctrl-p: views | ctrl-y: likes | ctrl-n: name | Enter: select',
            '--height', '100%',
            '--layout', 'reverse',
            '--info', 'inline',
            '--border', 'rounded',
            '--preview-window', 'hidden',
            '--ansi',
            '--bind', f'ctrl-o:change-prompt(> Select video (date): )+reload(cat {date_file})',
            '--bind', f'ctrl-p:change-prompt(> Select video (views): )+reload(cat {views_file})',
            '--bind', f'ctrl-y:change-prompt(> Select video (likes): )+reload(cat {likes_file})',
            '--bind', f'ctrl-n:change-prompt(> Select video (name): )+reload(cat {name_file})'
        ]
        
        result = subprocess.run(
            fzf_cmd,
            input=initial_input,
            capture_output=True,
            text=True
        )
        
        # Clean up temp files
        import os as os_module
        for temp_file in [date_file, views_file, likes_file, name_file]:
            try:
                os_module.unlink(temp_file)
            except:
                pass
        
        if result.returncode == 0 and result.stdout.strip():
            # Find the selected video
            selected_line = result.stdout.strip()
            # Remove the [SHORT] prefix if present for matching
            clean_line = selected_line.replace("[SHORT] ", "")
            
            for item in all_content:
                if format_video_for_fzf(item) == clean_line or f"[SHORT] {format_video_for_fzf(item)}" == selected_line:
                    selected_video = item
                    
                    # Fetch comments for the selected video if not already fetched
                    if 'comments' not in selected_video:
                        print("Fetching comments...")
                        selected_video['comments'] = get_video_comments(selected_video['id'])
                    
                    display_video_details(selected_video)
                    
                    # Ask if user wants to open in browser
                    response = input("Open in browser? (y/n): ")
                    if response.lower() == 'y':
                        url = f"https://www.youtube.com/watch?v={selected_video['id']}"
                        subprocess.run(['xdg-open', url])
                    break
        else:
            print("No video selected.")
            
    except FileNotFoundError:
        print("Error: fzf is not installed. Please install fzf to use interactive selection.")
        sys.exit(1)
    except Exception as e:
        print(f"Error during selection: {e}")
        sys.exit(1)

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

# Argument parser to add --shorts, --date, --comments, and --fzf flags
parser = argparse.ArgumentParser(description="Fetch YouTube video data")
parser.add_argument('--shorts', action='store_true', help='Include shorts statistics in the output')
parser.add_argument('--date', action='store_true', help='Sort by publication date instead of views')
parser.add_argument('--comments', action='store_true', help='Fetch and display comments for videos')
parser.add_argument('--fzf', action='store_true', help='Interactive selection mode using fzf')
args = parser.parse_args()

# Get videos and shorts with views and likes
print("Fetching video data..." + (" (this may take longer with comments)" if args.comments else ""))
videos, shorts = get_all_video_data(channel_id, fetch_comments=args.comments)

if args.fzf:
    # Interactive fzf mode
    interactive_fzf_selection(videos, shorts, args.shorts)
else:
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
