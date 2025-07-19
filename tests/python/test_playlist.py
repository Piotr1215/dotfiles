#!/usr/bin/env python3
"""
Unit tests for __append_to_playlist.py
"""
import os
import pathlib
import tempfile
import unittest
import sys

# Add scripts directory to path to import the module
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'scripts'))
from __append_to_playlist import (
    normalize_url,
    append_to_playlist,
    atomic_write,
    organize_with_claude
)

class TestNormalizeURL(unittest.TestCase):
    """Test URL normalization functionality."""
    
    def test_normalize_youtube_urls(self):
        """Test that YouTube URLs are normalized properly."""
        urls = [
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/watch?v=dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ", "https://youtube.com/watch?v=dQw4w9WgXcQ"),
            ("https://youtube.com/watch?v=dQw4w9WgXcQ&feature=shared", "https://youtube.com/watch?v=dQw4w9WgXcQ"),
        ]
        
        for input_url, expected_url in urls:
            with self.subTest(input_url=input_url):
                self.assertEqual(normalize_url(input_url), expected_url)
    
    def test_normalize_non_youtube_urls(self):
        """Test that non-YouTube URLs are normalized properly."""
        urls = [
            ("https://example.com/page/", "https://example.com/page"),
            ("https://example.com/page", "https://example.com/page"),
            ("HTTPS://EXAMPLE.COM/PAGE", "https://example.com/page"),
        ]
        
        for input_url, expected_url in urls:
            with self.subTest(input_url=input_url):
                self.assertEqual(normalize_url(input_url), expected_url)
    
    def test_handle_invalid_urls(self):
        """Test that invalid URLs don't crash the normalizer."""
        invalid_urls = [
            "not a url",
            "http:/example.com",  # Missing slash
            "",
        ]
        
        for url in invalid_urls:
            with self.subTest(url=url):
                # Should return the original URL if parsing fails
                self.assertEqual(normalize_url(url), url)

class TestAppendToPlaylist(unittest.TestCase):
    """Test playlist append functionality."""
    
    def setUp(self):
        """Create a temporary directory and file for testing."""
        self.test_dir = tempfile.TemporaryDirectory()
        self.test_playlist_path = os.path.join(self.test_dir.name, "test_playlist.txt")
        
        # Create a sample playlist
        with open(self.test_playlist_path, "w") as f:
            f.write("# AMBIENT/CALM: Test Track 1\n")
            f.write("https://youtube.com/watch?v=123456\n")
            f.write("# FOCUS/CODING: Test Track 2\n")
            f.write("https://youtube.com/watch?v=abcdef\n")
    
    def tearDown(self):
        """Clean up temporary files."""
        self.test_dir.cleanup()
    
    def test_append_new_track(self):
        """Test appending a new track to the playlist."""
        result = append_to_playlist(
            "https://youtube.com/watch?v=newtrack",
            "New Test Track",
            self.test_playlist_path,
            dry_run=False
        )
        
        self.assertTrue(result)
        
        # Verify the track was added
        with open(self.test_playlist_path, "r") as f:
            content = f.read()
        
        self.assertIn("# New Test Track", content)
        self.assertIn("https://youtube.com/watch?v=newtrack", content)
    
    def test_append_duplicate_track(self):
        """Test that duplicates are not added."""
        # Try to add a track with the same URL
        result = append_to_playlist(
            "https://youtube.com/watch?v=123456",
            "Duplicate Track",
            self.test_playlist_path,
            dry_run=False
        )
        
        self.assertFalse(result)
        
        # Verify the duplicate wasn't added
        with open(self.test_playlist_path, "r") as f:
            content = f.read()
        
        self.assertNotIn("# Duplicate Track", content)
    
    def test_append_normalized_duplicate(self):
        """Test that URL normalization prevents duplicates with different formats."""
        # Try to add a track with the same video ID but different URL format
        result = append_to_playlist(
            "https://youtu.be/123456",
            "Duplicate Track",
            self.test_playlist_path,
            dry_run=False
        )
        
        self.assertFalse(result)
        
        # Verify the normalized duplicate wasn't added
        with open(self.test_playlist_path, "r") as f:
            content = f.read()
        
        self.assertNotIn("# Duplicate Track", content)
    
    def test_append_with_genre_tag(self):
        """Test appending a track with an existing genre tag."""
        result = append_to_playlist(
            "https://youtube.com/watch?v=taggedtrack",
            "ELECTRONIC/CHILL: Tagged Track",
            self.test_playlist_path,
            dry_run=False
        )
        
        self.assertTrue(result)
        
        # Verify the track was added with its tag preserved
        with open(self.test_playlist_path, "r") as f:
            content = f.read()
        
        self.assertIn("# ELECTRONIC/CHILL: Tagged Track", content)
        
    def test_append_to_nonexistent_file(self):
        """Test appending to a file that doesn't exist yet."""
        nonexistent_path = os.path.join(self.test_dir.name, "new_playlist.txt")
        
        result = append_to_playlist(
            "https://youtube.com/watch?v=firsttrack",
            "First Track",
            nonexistent_path,
            dry_run=False
        )
        
        self.assertTrue(result)
        self.assertTrue(os.path.exists(nonexistent_path))
        
        # Verify the track was added to the new file
        with open(nonexistent_path, "r") as f:
            content = f.read()
        
        self.assertIn("# First Track", content)
        self.assertIn("https://youtube.com/watch?v=firsttrack", content)
    
    def test_append_with_dry_run(self):
        """Test that dry run mode doesn't modify the file."""
        original_content = pathlib.Path(self.test_playlist_path).read_text()
        
        result = append_to_playlist(
            "https://youtube.com/watch?v=dryrun",
            "Dry Run Track",
            self.test_playlist_path,
            dry_run=True
        )
        
        self.assertTrue(result)
        
        # Verify the file wasn't modified
        new_content = pathlib.Path(self.test_playlist_path).read_text()
        self.assertEqual(original_content, new_content)

class TestAtomicWrite(unittest.TestCase):
    """Test atomic write functionality."""
    
    def setUp(self):
        """Create a temporary directory for testing."""
        self.test_dir = tempfile.TemporaryDirectory()
        self.test_file_path = os.path.join(self.test_dir.name, "test_file.txt")
    
    def tearDown(self):
        """Clean up temporary files."""
        self.test_dir.cleanup()
    
    def test_atomic_write_new_file(self):
        """Test writing to a new file."""
        content = "Test content for new file"
        atomic_write(self.test_file_path, content)
        
        self.assertTrue(os.path.exists(self.test_file_path))
        
        with open(self.test_file_path, "r") as f:
            file_content = f.read()
        
        self.assertEqual(content, file_content)
    
    def test_atomic_write_existing_file(self):
        """Test overwriting an existing file."""
        # Create initial file
        with open(self.test_file_path, "w") as f:
            f.write("Initial content")
        
        # Atomically overwrite
        new_content = "New content replacing initial content"
        atomic_write(self.test_file_path, new_content)
        
        with open(self.test_file_path, "r") as f:
            file_content = f.read()
        
        self.assertEqual(new_content, file_content)
    
    def test_no_temp_files_remain(self):
        """Test that no temporary files are left behind."""
        content = "Test content"
        atomic_write(self.test_file_path, content)
        
        # Check for .tmp files in the directory
        temp_files = list(pathlib.Path(self.test_dir.name).glob("*.tmp"))
        self.assertEqual(len(temp_files), 0, f"Temp files remain: {temp_files}")

if __name__ == "__main__":
    unittest.main()