#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import email
from email.header import decode_header
from subprocess import Popen, PIPE
import tempfile
import mailbox
import argparse
import json
from datetime import datetime
import sys
import re
from bs4 import BeautifulSoup

class EmailExtractor:
    def __init__(self, base_path="/home/decoder/.local/share/mail/piotrzan@gmail.com"):
        self.base_path = base_path
        self.emails = []
        self.stats = {
            'total_emails': 0,
            'total_chars': 0,
            'total_words': 0,
            'folders_processed': set()
        }

    def clean_text(self, text):
        """Clean text content by removing extra whitespace and normalizing newlines."""
        if not text:
            return ""
        # Remove multiple newlines and whitespace
        text = re.sub(r'\n\s*\n', '\n\n', text)
        text = re.sub(r'[ \t]+', ' ', text)
        return text.strip()

    def html_to_text(self, html_content):
        """Convert HTML to plain text."""
        try:
            soup = BeautifulSoup(html_content, 'html.parser')
            # Remove script and style elements
            for script in soup(["script", "style"]):
                script.decompose()
            text = soup.get_text()
            return self.clean_text(text)
        except:
            return html_content

    def decode_email_header(self, header):
        """Decode email header to handle various encodings."""
        if not header:
            return ""
        try:
            decoded_header = decode_header(header)
            parts = []
            for text, charset in decoded_header:
                if isinstance(text, bytes):
                    text = text.decode(charset or 'utf-8', errors='replace')
                parts.append(str(text))
            return ' '.join(parts)
        except:
            return str(header)

    def extract_body(self, message):
        """Extract the email body, handling both text and HTML content."""
        body = None
        html = None
        
        # Try text/plain first
        for part in message.walk():
            if part.get_content_type() == "text/plain":
                if body is None:
                    body = ""
                try:
                    payload = part.get_payload(decode=True)
                    charset = part.get_content_charset() or 'utf-8'
                    body += payload.decode(charset, 'replace')
                except:
                    continue
        
        # Fall back to HTML if necessary
        if not body:
            for part in message.walk():
                if part.get_content_type() == "text/html":
                    try:
                        payload = part.get_payload(decode=True)
                        charset = part.get_content_charset() or 'utf-8'
                        html = payload.decode(charset, 'replace')
                        body = self.html_to_text(html)
                        break
                    except:
                        continue

        return self.clean_text(body or "No readable content found")

    def process_folder(self, folder_name, max_emails=None):
        """Process emails in a folder with optional limit."""
        folder_path = os.path.join(self.base_path, folder_name)
        
        if not os.path.exists(folder_path):
            print(f"Error: Folder does not exist: {folder_path}", file=sys.stderr)
            return
        
        try:
            mbox = mailbox.Maildir(folder_path)
        except Exception as e:
            print(f"Error opening maildir {folder_path}: {str(e)}", file=sys.stderr)
            return

        print(f"\nProcessing folder: {folder_name}", file=sys.stderr)
        
        email_count = 0
        for key, message in mbox.items():
            if max_emails and email_count >= max_emails:
                break
                
            try:
                # Extract headers
                from_addr = self.decode_email_header(message['From'])
                subject = self.decode_email_header(message['Subject'])
                date = message['Date']
                
                # Get body and clean it
                body = self.extract_body(message)
                
                # Store email data
                email_data = {
                    'folder': folder_name,
                    'from': from_addr,
                    'subject': subject,
                    'date': date,
                    'body': body
                }
                
                self.emails.append(email_data)
                self.stats['total_chars'] += len(body)
                self.stats['total_words'] += len(body.split())
                email_count += 1
                self.stats['total_emails'] += 1
                self.stats['folders_processed'].add(folder_name)

            except Exception as e:
                print(f"Error processing message {key}: {str(e)}", file=sys.stderr)
                continue

    def format_for_llm(self, max_chars=30000):
        """Format emails with more concise output and character limit."""
        output = "Here are the key emails for analysis:\n\n"
        current_chars = 0
        emails_included = 0
        
        for i, email in enumerate(self.emails, 1):
            email_text = (
                f"EMAIL {i}\n"
                f"{'=' * 40}\n"
                f"Folder: {email['folder']}\n"
                f"From: {email['from']}\n"
                f"Subject: {email['subject']}\n"
                f"Date: {email['date']}\n\n"
                f"Content:\n"
                f"{'-' * 40}\n"
                f"{email['body']}\n\n"
                f"{'=' * 80}\n\n"
            )
            
            # Check if adding this email would exceed the limit
            if current_chars + len(email_text) > max_chars:
                break
            
            output += email_text
            current_chars += len(email_text)
            emails_included += 1
        
        # Add summary
        summary = (
            f"\nProcessing Summary:\n"
            f"- Total emails found: {self.stats['total_emails']}\n"
            f"- Emails included in output: {emails_included}\n"
            f"- Total characters: {current_chars:,}\n"
            f"- Average chars per email: {current_chars // emails_included if emails_included else 0:,}\n"
            f"- Folders processed: {', '.join(self.stats['folders_processed'])}\n"
        )
        
        return output + summary, current_chars, emails_included

def main():
    parser = argparse.ArgumentParser(description='Extract and analyze emails')
    parser.add_argument('--folder', help='Specific folder to process')
    parser.add_argument('--all', action='store_true', help='Process all folders')
    parser.add_argument('--max-emails', type=int, help='Maximum number of emails to process per folder')
    parser.add_argument('--max-chars', type=int, default=30000, 
                       help='Maximum characters to send to LLM (default: 30000)')
    parser.add_argument('--analyze', action='store_true', 
                       help='Send to fabric for analysis (default: just show output)')
    
    args = parser.parse_args()
    
    extractor = EmailExtractor()
    
    if args.all:
        folders = [d for d in os.listdir(extractor.base_path) 
                  if os.path.isdir(os.path.join(extractor.base_path, d))]
    elif args.folder:
        folders = [args.folder]
    else:
        parser.print_help()
        return

    # Process folders
    for folder in folders:
        extractor.process_folder(folder, args.max_emails)

    # Format and get statistics
    formatted_output, char_count, emails_included = extractor.format_for_llm(args.max_chars)
    
    if args.analyze:
        try:
            print("\nSending to fabric for analysis...", file=sys.stderr)
            process = Popen(['fabric', '-p', 'email-organizer'], 
                          stdin=PIPE, stdout=PIPE, stderr=PIPE, text=True)
            output, error = process.communicate(input=formatted_output)
            
            if error:
                print("Fabric error:", error, file=sys.stderr)
            print(output)
            
        except Exception as e:
            print(f"Error running fabric: {str(e)}", file=sys.stderr)
            print(formatted_output)
    else:
        print(formatted_output)

if __name__ == "__main__":
    main()
