#!/usr/bin/env python3

import gi
import os
import signal
import subprocess
import sys
from threading import Lock

# Required for AppIndicator
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
from gi.repository import Gtk, AppIndicator3, GLib

GAME_MODE_FLAG = "/tmp/game_mode_active"
UPDATE_INTERVAL = 2  # seconds
SCRIPT_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "__toggle_services.sh")

class GameModeIndicator:
    def __init__(self):
        self.app = "gamemode-indicator"
        self.update_lock = Lock()  # Lock for thread-safe updates
        
        # Set up signal handler for SIGUSR1
        signal.signal(signal.SIGUSR1, self.handle_update_signal)
        
        # Create the indicator
        self.indicator = AppIndicator3.Indicator.new(
            self.app,
            "input-gaming",  # Default icon (gaming controller)
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        
        # Set properties
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        
        # Create menu
        self.menu = self.create_menu()
        self.indicator.set_menu(self.menu)
        
        # Initial icon update
        self.update_icon()
        
        # Set up periodic icon updates
        GLib.timeout_add_seconds(UPDATE_INTERVAL, self.update_icon)

    def create_menu(self):
        menu = Gtk.Menu()
        
        # Toggle item
        self.toggle_item = Gtk.MenuItem(label="Toggle Game Mode")
        self.toggle_item.connect("activate", self.toggle_mode)
        menu.append(self.toggle_item)
        
        # Separator
        separator1 = Gtk.SeparatorMenuItem()
        menu.append(separator1)
        
        # Status item (readonly)
        self.status_item = Gtk.MenuItem(label="Status: Checking...")
        self.status_item.set_sensitive(False)  # Non-clickable
        menu.append(self.status_item)
        
        # Separator
        separator2 = Gtk.SeparatorMenuItem()
        menu.append(separator2)
        
        # Quit item
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self.quit)
        menu.append(quit_item)
        
        menu.show_all()
        return menu

    def update_icon(self):
        with self.update_lock:  # Thread-safe update
            is_game_mode = os.path.exists(GAME_MODE_FLAG)
            
            if is_game_mode:
                # Gaming mode active
                self.indicator.set_icon_full("input-gaming", "Gaming Mode Active")
                self.indicator.set_label("🎮", "")
                self.toggle_item.set_label("Disable Game Mode")
                
                # Update status label
                self.status_item.set_label("Status: GAME MODE ACTIVE")
            else:
                # Normal mode
                self.indicator.set_icon_full("computer", "Normal Mode")
                self.indicator.set_label("🖥️", "")
                self.toggle_item.set_label("Enable Game Mode")
                
                # Update status label
                self.status_item.set_label("Status: Normal Mode")
        
        return True  # Continue the timer
        
    def handle_update_signal(self, signum, frame):
        # This will be called when the toggle script sends SIGUSR1
        GLib.idle_add(self.update_icon)
        
    def toggle_mode(self, widget):
        """Toggle game mode on/off"""
        try:
            # Run the toggle script
            subprocess.run(
                ["bash", SCRIPT_PATH],
                check=True
            )
            
            # Update icon immediately
            self.update_icon()
        except Exception as e:
            print(f"Error toggling game mode: {e}")
            
    def quit(self, widget):
        Gtk.main_quit()
        
if __name__ == "__main__":
    # Handle Ctrl+C gracefully
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    
    # Start the indicator
    indicator = GameModeIndicator()
    Gtk.main()