#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __toggle_services.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

SERVICES="
docker.service
containerd.service
snapd.service
packagekit.service
avahi-daemon.service
cups.service
cups-browsed.service
tailscaled.service
bluetooth.service
NetworkManager-wait-online.service
fwupd.service
ModemManager.service
rsyslog.service
cron.service
thermald.service
"

PROCESSES="
gnome-software
evolution
tracker-miner-fs
tracker-extract
tracker-store
zeitgeist-datahub
zeitgeist-daemon
gnome-shell-calendar-server
gsd-housekeeping
"

# Store original system values
ORIGINAL_SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
ORIGINAL_VFS_CACHE_PRESSURE=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "100")
ORIGINAL_MAX_USER_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "8192")

# Print title with gum style
gum style --foreground 212 --bold "🎮 Ultimate Game Mode Toggler 🎮"

# Function to measure system resources
measure_resources() {
  # Get CPU usage percentage (average of all cores)
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
  
  # Get memory usage in MB
  mem_total=$(free -m | awk '/Mem:/ {print $2}')
  mem_used=$(free -m | awk '/Mem:/ {print $3}')
  mem_usage=$((mem_used * 100 / mem_total))
  
  # Count running processes
  process_count=$(ps aux | wc -l)
  
  echo "$cpu_usage $mem_used $mem_usage $process_count"
}

# Check if majority of services are running
check_running() {
  running=0
  total=0
  for service in $SERVICES; do
    total=$((total+1))
    if systemctl is-active --quiet "$service"; then
      running=$((running+1))
    fi
  done
  
  # If more than half are running, consider the set as "running"
  if [ $running -gt $(($total/2)) ]; then
    return 0
  else
    return 1
  fi
}

# Create game mode config file
create_gamemode_config() {
  if [ ! -d "/etc/gamemode.d" ]; then
    sudo mkdir -p /etc/gamemode.d
  fi
  
  sudo tee /etc/gamemode.d/gamemode.ini > /dev/null << 'EOT'
[general]
; GameMode CPU governor
desiredgov=performance
; Default CPU governor
defaultgov=ondemand
; Renice games
renice=10
; Reapply CPU and iGPU optimisations
softrealtime=auto
; Inhibit screensaver
inhibit_screensaver=1

[custom]
; Custom scripts
start=
end=
EOT
}

# Store original I/O schedulers
store_io_schedulers() {
  # Create temporary file to store original schedulers
  echo "" > /tmp/original_io_schedulers.txt
  
  for disk in /sys/block/sd* /sys/block/nvme*; do
    if [ -e "$disk/queue/scheduler" ]; then
      current=$(cat "$disk/queue/scheduler" | grep -o "\[.*\]" | tr -d "[]")
      echo "$(basename $disk) $current" >> /tmp/original_io_schedulers.txt
    fi
  done
}

# Restore original I/O schedulers
restore_io_schedulers() {
  if [ -f "/tmp/original_io_schedulers.txt" ]; then
    while read line; do
      if [ ! -z "$line" ]; then
        disk=$(echo $line | cut -d' ' -f1)
        scheduler=$(echo $line | cut -d' ' -f2)
        
        if [ -e "/sys/block/$disk/queue/scheduler" ]; then
          gum spin --spinner dot --title "Restoring I/O scheduler for $disk..." -- sudo bash -c "echo $scheduler > /sys/block/$disk/queue/scheduler 2>/dev/null || true"
        fi
      fi
    done < /tmp/original_io_schedulers.txt
  fi
}

# Measure resources before changes
gum style --foreground 39 "Measuring current resource usage..."
before_resources=$(measure_resources)
before_cpu=$(echo $before_resources | cut -d' ' -f1)
before_mem_used=$(echo $before_resources | cut -d' ' -f2)
before_mem_percent=$(echo $before_resources | cut -d' ' -f3)
before_processes=$(echo $before_resources | cut -d' ' -f4)

# Toggle services with gum spinner and handle errors
if check_running; then
  gum style --foreground 208 "Stopping services for better gaming performance..."
  
  # Store original I/O schedulers before changing them
  store_io_schedulers
  
  # Stop services
  for service in $SERVICES; do
    if systemctl is-active --quiet "$service"; then
      gum spin --spinner dot --title "Stopping $service..." -- bash -c "sudo systemctl stop $service || true"
    else
      gum style --foreground 245 "⏭️  Skipping $service (already stopped)"
    fi
  done
  
  # Kill resource-intensive processes
  for proc in $PROCESSES; do
    if pgrep -f "$proc" > /dev/null; then
      gum spin --spinner dot --title "Killing $proc..." -- bash -c "killall -9 $proc 2>/dev/null || true"
    else
      gum style --foreground 245 "⏭️  Skipping $proc (not running)"
    fi
  done
  
  # Set CPU governor to performance if available
  if command -v cpupower > /dev/null && grep -q "performance" /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null; then
    gum spin --spinner dot --title "Setting CPU governor to performance..." -- sudo cpupower frequency-set -g performance
  fi
  
  # Disable compositor if running
  if pgrep -f "picom|compton|xcompmgr" > /dev/null; then
    gum spin --spinner dot --title "Disabling compositor..." -- bash -c "killall picom compton xcompmgr 2>/dev/null || true"
  elif pgrep -f "gnome-shell" > /dev/null; then
    # Store current GNOME settings
    current_effects=$(gsettings get org.gnome.mutter experimental-features 2>/dev/null || echo "[]")
    echo "$current_effects" > /tmp/gnome_effects.txt
    
    gum spin --spinner dot --title "Disabling GNOME compositor effects..." -- bash -c "gsettings set org.gnome.mutter experimental-features '[]' || true"
  fi
  
  # Set process priorities for Steam
  if pgrep -f "steam" > /dev/null; then
    gum spin --spinner dot --title "Setting Steam process priority..." -- bash -c "for pid in \$(pgrep -f steam); do sudo renice -n -5 \$pid 2>/dev/null || true; done"
  fi
  
  # Drop disk caches to free up memory
  gum spin --spinner dot --title "Dropping disk caches..." -- sudo bash -c "echo 1 > /proc/sys/vm/drop_caches"
  
  # Set I/O scheduler to deadline for better responsiveness
  for disk in /sys/block/sd* /sys/block/nvme*; do
    if [ -e "$disk/queue/scheduler" ]; then
      gum spin --spinner dot --title "Setting I/O scheduler for $(basename $disk)..." -- sudo bash -c "echo deadline > $disk/queue/scheduler 2>/dev/null || true"
    fi
  done
  
  # Optimize swappiness
  gum spin --spinner dot --title "Reducing swappiness..." -- sudo bash -c "echo 10 > /proc/sys/vm/swappiness"
  
  # Optimize VFS cache pressure
  gum spin --spinner dot --title "Optimizing VFS cache pressure..." -- sudo bash -c "echo 50 > /proc/sys/vm/vfs_cache_pressure"
  
  # Set max user watches for games that need to monitor many files
  gum spin --spinner dot --title "Increasing max user watches..." -- sudo bash -c "echo 524288 > /proc/sys/fs/inotify/max_user_watches"
  
  # Disable NVIDIA GPU power management if NVIDIA GPU is present
  if command -v nvidia-smi > /dev/null; then
    gum spin --spinner dot --title "Setting NVIDIA GPU to maximum performance..." -- sudo bash -c "nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=1' 2>/dev/null || true"
  fi
  
  # Set up GameMode if installed
  if command -v gamemoded > /dev/null; then
    gum spin --spinner dot --title "Configuring GameMode..." -- bash -c "$(create_gamemode_config)"
  fi
  
  # Set up environment variables for Steam
  if [ -d "$HOME/.steam" ]; then
    gum spin --spinner dot --title "Setting up Steam environment variables..." -- bash -c "echo 'DXVK_ASYNC=1' > $HOME/.steam/steam.env && echo 'PROTON_NO_FSYNC=0' >> $HOME/.steam/steam.env && echo 'PROTON_HIDE_NVIDIA_GPU=0' >> $HOME/.steam/steam.env && echo 'PROTON_ENABLE_NVAPI=1' >> $HOME/.steam/steam.env"
  fi
  
  # Create a flag file to indicate we're in game mode
  mkdir -p "$HOME/.local/share/gamemode"
  echo "1" > "$HOME/.local/share/gamemode/game_mode_active"
  
  gum style --foreground 46 --bold "✅ Ultimate Game Mode Activated! Services stopped successfully."
else
  gum style --foreground 39 "Starting services..."
  
  # Start services
  for service in $SERVICES; do
    if ! systemctl is-active --quiet "$service"; then
      gum spin --spinner dot --title "Starting $service..." -- bash -c "sudo systemctl start $service || true"
    else
      gum style --foreground 245 "⏭️  Skipping $service (already running)"
    fi
  done
  
  # Reset CPU governor to ondemand if available
  if command -v cpupower > /dev/null && grep -q "ondemand" /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null; then
    gum spin --spinner dot --title "Setting CPU governor to ondemand..." -- sudo cpupower frequency-set -g ondemand
  fi
  
  # Restore original I/O schedulers
  restore_io_schedulers
  
  # Reset swappiness to original value
  gum spin --spinner dot --title "Resetting swappiness..." -- sudo bash -c "echo $ORIGINAL_SWAPPINESS > /proc/sys/vm/swappiness"
  
  # Reset VFS cache pressure to original value
  gum spin --spinner dot --title "Resetting VFS cache pressure..." -- sudo bash -c "echo $ORIGINAL_VFS_CACHE_PRESSURE > /proc/sys/vm/vfs_cache_pressure"
  
  # Reset max user watches to original value
  gum spin --spinner dot --title "Resetting max user watches..." -- sudo bash -c "echo $ORIGINAL_MAX_USER_WATCHES > /proc/sys/fs/inotify/max_user_watches"
  
  # Re-enable GNOME compositor effects if GNOME is running
  if pgrep -f "gnome-shell" > /dev/null && [ -f "/tmp/gnome_effects.txt" ]; then
    original_effects=$(cat /tmp/gnome_effects.txt)
    gum spin --spinner dot --title "Re-enabling GNOME compositor effects..." -- bash -c "gsettings set org.gnome.mutter experimental-features \"$original_effects\" || true"
    rm -f /tmp/gnome_effects.txt
  fi
  
  # Reset NVIDIA GPU power management if NVIDIA GPU is present
  if command -v nvidia-smi > /dev/null; then
    gum spin --spinner dot --title "Resetting NVIDIA GPU power management..." -- sudo bash -c "nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=0' 2>/dev/null || true"
  fi
  
  # Remove Steam environment variables
  if [ -f "$HOME/.steam/steam.env" ]; then
    gum spin --spinner dot --title "Removing Steam environment variables..." -- bash -c "rm -f $HOME/.steam/steam.env"
  fi
  
  # Remove game mode flag
  rm -f "$HOME/.local/share/gamemode/game_mode_active"
  
  gum style --foreground 46 --bold "✅ Normal Mode Restored! Services started successfully."
fi

# Wait a moment for system to stabilize
sleep 2

# Measure resources after changes
gum style --foreground 39 "Measuring new resource usage..."
after_resources=$(measure_resources)
after_cpu=$(echo $after_resources | cut -d' ' -f1)
after_mem_used=$(echo $after_resources | cut -d' ' -f2)
after_mem_percent=$(echo $after_resources | cut -d' ' -f3)
after_processes=$(echo $after_resources | cut -d' ' -f4)

# Calculate differences (using bc for floating point)
cpu_diff=$(echo "$before_cpu - $after_cpu" | bc)
mem_diff=$(echo "$before_mem_used - $after_mem_used" | bc)
mem_percent_diff=$(echo "$before_mem_percent - $after_mem_percent" | bc)
process_diff=$(echo "$before_processes - $after_processes" | bc)

# Determine if values increased or decreased
if (( $(echo "$cpu_diff >= 0" | bc -l) )); then
  cpu_arrow="↓"
  cpu_color="46" # green
else
  cpu_arrow="↑"
  cpu_color="196" # red
  cpu_diff=$(echo "$cpu_diff * -1" | bc)
fi


if (( $(echo "$mem_diff >= 0" | bc -l) )); then
  mem_arrow="↓"
  mem_color="46" # green
else
  mem_arrow="↑"
  mem_color="196" # red
  mem_diff=$(echo "$mem_diff * -1" | bc)
fi

if (( $(echo "$mem_percent_diff >= 0" | bc -l) )); then
  mem_percent_arrow="↓"
  mem_percent_color="46" # green
else
  mem_percent_arrow="↑"
  mem_percent_color="196" # red
  mem_percent_diff=$(echo "$mem_percent_diff * -1" | bc)
fi

if (( $(echo "$process_diff >= 0" | bc -l) )); then
  process_arrow="↓"
  process_color="46" # green
else
  process_arrow="↑"
  process_color="196" # red
  process_diff=$(echo "$process_diff * -1" | bc)
fi

# Display resource changes with colors
gum style --foreground 226 --bold "📊 Resource Changes:"
gum style "CPU Usage: ${before_cpu}% → ${after_cpu}% ($(gum style --foreground $cpu_color "${cpu_arrow} ${cpu_diff}%"))"
gum style "Memory Used: ${before_mem_used}MB → ${after_mem_used}MB ($(gum style --foreground $mem_color "${mem_arrow} ${mem_diff}MB"))"
gum style "Memory Usage: ${before_mem_percent}% → ${after_mem_percent}% ($(gum style --foreground $mem_percent_color "${mem_percent_arrow} ${mem_percent_diff}%"))"
gum style "Running Processes: ${before_processes} → ${after_processes} ($(gum style --foreground $process_color "${process_arrow} ${process_diff}"))"

# Check if we're in game mode and show appropriate tips
if [ -f "$HOME/.local/share/gamemode/game_mode_active" ]; then
  gum style --foreground 226 --bold "🎮 Game Mode Active"
  gum style "• System optimized for gaming performance"
else
  gum style --foreground 226 --bold "🖥️ System Restored:"
  gum style "• All services have been restored to their original state"
  gum style "• System settings have been reset to normal operation"
  gum style "• Run this script again before launching games for best performance"
fi

