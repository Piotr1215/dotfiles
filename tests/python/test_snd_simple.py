#!/usr/bin/env python3
"""
Simple tests for snd script to verify functionality
Tests the script directly by running it as a subprocess
"""
import os
import sys
import unittest
import subprocess
from unittest.mock import patch, MagicMock

class TestSndScript(unittest.TestCase):
    """Test snd script functionality."""
    
    def setUp(self):
        self.snd_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            'scripts', 'snd'
        )
    
    @patch('subprocess.run')
    def test_script_exists(self, mock_run):
        """Test that the snd script exists."""
        self.assertTrue(os.path.exists(self.snd_path))
        self.assertTrue(os.access(self.snd_path, os.X_OK))
    
    def test_help_output(self):
        """Test that snd --help works."""
        result = subprocess.run(
            [sys.executable, self.snd_path, '--help'],
            capture_output=True,
            text=True
        )
        self.assertIn('Send messages to Claude tmux panes', result.stdout)
        self.assertIn('--agents', result.stdout)

if __name__ == '__main__':
    unittest.main()