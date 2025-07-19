#!/usr/bin/env python3
"""
Unit tests for snd script
Tests the --agents flag functionality and backward compatibility
"""
import os
import sys
import unittest
import subprocess
from unittest.mock import patch, MagicMock, call

# Add parent directory to path to import the snd script
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class TestSndScript(unittest.TestCase):
    """Test snd script functionality."""
    
    @patch('subprocess.run')
    def test_agents_flag_filters_correctly(self, mock_run):
        """Test that --agents flag only sends to panes with @agent_name."""
        # Mock tmux list-panes output
        mock_run.return_value.stdout = """poke:1.1 developer
poke:1.2 
poke:1.3 minimi
claude:1.1 """
        mock_run.return_value.returncode = 0
        
        # Import and run snd with --agents flag
        from snd import main
        with patch('sys.argv', ['snd', '--agents', 'test message']):
            result = main()
        
        # Verify tmux list-panes was called correctly
        list_panes_call = call(['tmux', 'list-panes', '-a', '-F', 
                               '#{session_name}:#{window_index}.#{pane_index} #{?#{@agent_name},#{@agent_name},}'],
                              capture_output=True, text=True)
        
        # Verify send-keys was called only for agent panes
        expected_sends = [
            call(['tmux', 'send-keys', '-t', 'poke:1.1', 'test message']),
            call(['tmux', 'send-keys', '-t', 'poke:1.1', 'C-m']),
            call(['tmux', 'send-keys', '-t', 'poke:1.3', 'test message']),
            call(['tmux', 'send-keys', '-t', 'poke:1.3', 'C-m'])
        ]
        
        # Check that list-panes was called
        assert list_panes_call in mock_run.call_args_list
        
        # Check that messages were sent to correct panes
        for expected_call in expected_sends:
            assert expected_call in mock_run.call_args_list
            
    @patch('subprocess.run')
    def test_default_behavior_preserved(self, mock_run):
        """Test that default behavior (no --agents) still works."""
        # First call: list-panes with PIDs
        list_result = MagicMock()
        list_result.stdout = """poke:1.1 1234
poke:1.2 5678"""
        list_result.returncode = 0
        
        # Second/third calls: ps to check for __claude_with_monitor.sh
        ps_result1 = MagicMock()
        ps_result1.stdout = "__claude_with_monitor.sh"
        ps_result1.returncode = 0
        
        ps_result2 = MagicMock()
        ps_result2.stdout = "some_other_process"
        ps_result2.returncode = 0
        
        mock_run.side_effect = [list_result, ps_result1, ps_result2, 
                               MagicMock(), MagicMock()]  # send-keys calls
        
        from snd import main
        with patch('sys.argv', ['snd', 'test message']):
            result = main()
        
        # Verify only pane with __claude_with_monitor.sh received message
        send_calls = [
            call(['tmux', 'send-keys', '-t', 'poke:1.1', 'test message']),
            call(['tmux', 'send-keys', '-t', 'poke:1.1', 'C-m'])
        ]
        
        for expected_call in send_calls:
            assert expected_call in mock_run.call_args_list
            
    @patch('subprocess.run')
    def test_no_agent_panes_found(self, mock_run):
        """Test behavior when no agent panes are found."""
        # Mock empty output
        mock_run.return_value.stdout = """poke:1.1 
poke:1.2 """
        mock_run.return_value.returncode = 0
        
        from snd import main
        with patch('sys.argv', ['snd', '--agents']):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertEqual(cm.exception.code, 1)
            
    @patch('subprocess.run')
    def test_default_message_when_no_args(self, mock_run):
        """Test that default message is used when no text provided."""
        mock_run.return_value.stdout = "poke:1.1 developer"
        mock_run.return_value.returncode = 0
        
        from snd import main
        with patch('sys.argv', ['snd', '--agents']):
            result = main()
            
        # Check default message was sent
        default_msg_call = call(['tmux', 'send-keys', '-t', 'poke:1.1', 
                                'read my broadcast and keep collaborating'])
        assert default_msg_call in mock_run.call_args_list

if __name__ == '__main__':
    unittest.main()