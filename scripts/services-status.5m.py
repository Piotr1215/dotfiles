#!/usr/bin/env python3

# Service Status Monitor for Argos
# Monitors AWS, GCP, Azure, Netlify, GitHub, Linear, and GoDaddy status pages

import json
import urllib.request
import urllib.error
from datetime import datetime
import os
import base64
import tempfile
import hashlib
import subprocess

# Service configurations with status page URLs
SERVICES = {
    "AWS": {
        "api": "https://status.aws.amazon.com/data.json",
        "status_page": "https://status.aws.amazon.com/",
        "name": "Amazon Web Services",
        "favicon": "https://a0.awsstatic.com/libra-css/images/site/fav/favicon.ico"
    },
    "GCP": {
        "api": "https://status.cloud.google.com/incidents.json",
        "status_page": "https://status.cloud.google.com/",
        "name": "Google Cloud Platform",
        "favicon": "https://www.gstatic.com/devrel-devsite/prod/v85e39fe21f53c758adf7ff72d4b9c9b569d547f8e0e2b807668e509ad2a4914e/cloud/images/favicons/onecloud/favicon.ico"
    },
    "Azure": {
        "api": "https://status.azure.com/en-us/status/feed/",
        "status_page": "https://status.azure.com/en-us/status",
        "name": "Microsoft Azure",
        "favicon": "https://azure.microsoft.com/favicon.ico"
    },
    "Netlify": {
        "api": "https://www.netlifystatus.com/api/v2/status.json",
        "status_page": "https://www.netlifystatus.com/",
        "name": "Netlify",
        "favicon": "https://www.netlify.com/favicon.ico"
    },
    "GitHub": {
        "api": "https://www.githubstatus.com/api/v2/status.json",
        "status_page": "https://www.githubstatus.com/",
        "name": "GitHub",
        "favicon": "https://github.githubassets.com/favicons/favicon.png"
    },
    "Linear": {
        "api": "https://linearstatus.com/api/v2/status.json",
        "status_page": "https://linearstatus.com/",
        "name": "Linear",
        "favicon": "https://linear.app/favicon.ico"
    },
    "GoDaddy": {
        "api": "https://status.godaddy.com/api/v2/status.json",
        "status_page": "https://status.godaddy.com/",
        "name": "GoDaddy",
        "favicon": "https://www.godaddy.com/favicon.ico"
    },
    "Claude": {
        "api": "https://status.anthropic.com/api/v2/status.json",
        "status_page": "https://status.anthropic.com/",
        "name": "Claude",
        "favicon": "https://claude.ai/favicon.ico"
    },
    "Quay": {
        "api": "https://status.redhat.com/api/v2/status.json",
        "status_page": "https://status.redhat.com/",
        "name": "Quay.io",
        "favicon": "https://quay.io/static/img/favicon.ico"
    }
}

# Traffic light icons
ICONS = {
    "operational": "🟢",
    "degraded": "🟡",
    "partial": "🟡",
    "major": "🔴",
    "critical": "🔴",
    "unknown": "⚪"
}

# Service emoji representations
SERVICE_EMOJIS = {
    "AWS": "☁️",      # Cloud for AWS
    "GCP": "🔵",      # Blue circle for Google
    "Azure": "🔷",    # Blue diamond for Azure
    "Netlify": "🚀",  # Rocket for Netlify deployments
    "GitHub": "🐙",   # Octopus (Octocat) for GitHub
    "Linear": "📋",   # Clipboard for Linear issues
    "GoDaddy": "🌐", # Globe for domain registrar
    "Claude": "🤖",   # Robot for AI
    "Quay": "🐳"      # Whale/Docker for container registry
}

# Cache directory for favicons
CACHE_DIR = os.path.join(tempfile.gettempdir(), 'argos-favicons')
os.makedirs(CACHE_DIR, exist_ok=True)

# State file for tracking status changes
STATE_DIR = os.path.join(os.path.expanduser('~'), '.local', 'state', 'argos-service-monitor')
os.makedirs(STATE_DIR, exist_ok=True)
STATE_FILE = os.path.join(STATE_DIR, 'services_status_state.json')
SESSION_LAUNCHED_FILE = os.path.join(STATE_DIR, 'servmon_session_launched')

def get_cache_path(url):
    """Generate cache file path for a favicon URL"""
    url_hash = hashlib.md5(url.encode()).hexdigest()
    return os.path.join(CACHE_DIR, f"{url_hash}.b64")

def fetch_favicon(url, timeout=3):
    """Fetch favicon and return as base64 encoded data"""
    cache_path = get_cache_path(url)
    
    # Check cache first (cache for 24 hours)
    if os.path.exists(cache_path):
        cache_age = datetime.now().timestamp() - os.path.getmtime(cache_path)
        if cache_age < 86400:  # 24 hours
            try:
                with open(cache_path, 'r') as f:
                    return f.read()
            except Exception:
                pass
    
    # Fetch fresh favicon
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            favicon_data = response.read()
            # Convert to base64
            b64_data = base64.b64encode(favicon_data).decode('utf-8')
            
            # Cache the result
            try:
                with open(cache_path, 'w') as f:
                    f.write(b64_data)
            except Exception:
                pass
            
            return b64_data
    except Exception:
        return None

def fetch_status(url, timeout=5):
    """Fetch status from API endpoint"""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception:
        return None

def get_claude_status():
    """Check Claude status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Claude"]["api"])
        if data and 'status' in data:
            indicator = data['status'].get('indicator', 'none')
            if indicator == 'none':
                return "operational"
            elif indicator == 'minor':
                return "degraded"
            elif indicator in ['major', 'critical']:
                return "major"
    except Exception:
        pass
    return "unknown"

def get_quay_status():
    """Check Quay.io status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Quay"]["api"])
        if data and 'status' in data:
            indicator = data['status'].get('indicator', 'none')
            if indicator == 'none':
                return "operational"
            elif indicator == 'minor':
                return "degraded"
            elif indicator in ['major', 'critical']:
                return "major"
    except Exception:
        pass
    return "unknown"

def get_aws_status():
    """Check AWS status"""
    try:
        # AWS has a complex status structure, fallback to checking if API responds
        data = fetch_status(SERVICES["AWS"]["api"])
        if data:
            # If we get valid data, check for any current issues
            has_issues = False
            if isinstance(data, list):
                for service in data:
                    if isinstance(service, dict) and service.get('current'):
                        if len(service['current']) > 0:
                            has_issues = True
                            break
            return "degraded" if has_issues else "operational"
        else:
            # Try simpler health check endpoint
            health_url = "https://health.aws.amazon.com/health/status"
            req = urllib.request.Request(health_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    return "operational"
    except Exception:
        pass
    return "operational"  # Default to operational for AWS

def get_gcp_status():
    """Check GCP status"""
    try:
        data = fetch_status(SERVICES["GCP"]["api"])
        if data and isinstance(data, list):
            # Check only for active/ongoing incidents
            active_incidents = 0
            for incident in data:
                if isinstance(incident, dict):
                    # Check if incident is not resolved
                    if not incident.get('end', None):
                        active_incidents += 1
            return "degraded" if active_incidents > 0 else "operational"
        return "operational"
    except Exception:
        pass
    return "operational"  # Default to operational

def get_azure_status():
    """Check Azure status - using RSS feed as fallback"""
    try:
        # Azure's status API is complex, so we'll check for the page availability
        req = urllib.request.Request(SERVICES["Azure"]["status_page"], 
                                   headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                content = response.read().decode('utf-8')
                if 'healthy' in content.lower() or 'good' in content.lower():
                    return "operational"
                elif 'issue' in content.lower() or 'problem' in content.lower():
                    return "degraded"
                return "operational"  # Default to operational if page loads
    except Exception:
        pass
    return "unknown"

def get_netlify_status():
    """Check Netlify status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Netlify"]["api"])
        if data and 'status' in data:
            indicator = data['status'].get('indicator', 'none')
            if indicator == 'none':
                return "operational"
            elif indicator == 'minor':
                return "degraded"
            elif indicator in ['major', 'critical']:
                return "major"
    except Exception:
        pass
    return "unknown"

def get_github_status():
    """Check GitHub status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["GitHub"]["api"])
        if data and 'status' in data:
            indicator = data['status'].get('indicator', 'none')
            if indicator == 'none':
                return "operational"
            elif indicator == 'minor':
                return "degraded"
            elif indicator in ['major', 'critical']:
                return "major"
    except Exception:
        pass
    return "unknown"

def get_linear_status():
    """Check Linear status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Linear"]["api"])
        if data and 'status' in data:
            indicator = data['status'].get('indicator', 'none')
            if indicator == 'none':
                return "operational"
            elif indicator == 'minor':
                return "degraded"
            elif indicator in ['major', 'critical']:
                return "major"
    except Exception:
        pass
    return "unknown"

def get_godaddy_status():
    """Check GoDaddy status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["GoDaddy"]["api"])
        if data and 'status' in data:
            indicator = data['status'].get('indicator', 'none')
            if indicator == 'none':
                return "operational"
            elif indicator == 'minor':
                return "degraded"
            elif indicator in ['major', 'critical']:
                return "major"
    except Exception:
        pass
    return "unknown"

def get_all_statuses():
    """Get status for all services"""
    return {
        "AWS": get_aws_status(),
        "GCP": get_gcp_status(),
        "Azure": get_azure_status(),
        "Netlify": get_netlify_status(),
        "GitHub": get_github_status(),
        "Linear": get_linear_status(),
        "GoDaddy": get_godaddy_status(),
        "Claude": get_claude_status(),
        "Quay": get_quay_status()
    }

def get_overall_status(statuses):
    """Determine overall status based on individual service statuses"""
    status_values = list(statuses.values())
    
    if any(status in ["major", "critical"] for status in status_values):
        return "major"
    elif any(status in ["degraded", "partial"] for status in status_values):
        return "degraded"
    elif all(status == "operational" for status in status_values):
        return "operational"
    else:
        return "unknown"

def load_previous_state():
    """Load previous service states from file"""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r') as f:
                data = json.load(f)
                # Ensure backward compatibility
                if isinstance(data, dict) and 'statuses' not in data:
                    # Old format - just statuses
                    return {'statuses': data, 'degradation_counts': {}}
                return data
        except:
            pass
    return {'statuses': {}, 'degradation_counts': {}}

def save_current_state(statuses, degradation_counts):
    """Save current service states to file"""
    try:
        state_data = {
            'statuses': statuses,
            'degradation_counts': degradation_counts,
            'last_updated': datetime.now().isoformat()
        }
        with open(STATE_FILE, 'w') as f:
            json.dump(state_data, f, indent=2)
    except Exception:
        pass

def check_status_degradation(previous_statuses, current_statuses, degradation_counts):
    """Check if any service has sustained degradation (debouncing)"""
    degraded_services = []
    new_degradation_counts = degradation_counts.copy()
    
    for service, current_status in current_statuses.items():
        # Check if service is currently degraded
        if current_status in ["degraded", "partial", "major", "critical"]:
            # Increment degradation count
            new_degradation_counts[service] = new_degradation_counts.get(service, 0) + 1
            
            # Only report as degraded after 2 consecutive checks (10 minutes)
            if new_degradation_counts[service] >= 2:
                degraded_services.append((service, current_status))
        else:
            # Service is operational, reset count
            new_degradation_counts[service] = 0
    
    return degraded_services, new_degradation_counts

def launch_servmon_session():
    """Launch tmuxinator servmon session if not already running"""
    try:
        # Check if servmon session already exists
        result = subprocess.run(['tmux', 'has-session', '-t', 'servmon'], 
                              capture_output=True)
        
        if result.returncode != 0:
            # Session doesn't exist, launch it
            subprocess.run(['tmuxinator', 'start', 'servmon'], 
                         capture_output=True)
            return True
    except Exception:
        pass
    return False

def kill_servmon_session():
    """Kill servmon session if it exists"""
    try:
        result = subprocess.run(['tmux', 'has-session', '-t', 'servmon'], 
                              capture_output=True)
        
        if result.returncode == 0:
            # Session exists, kill it
            subprocess.run(['tmux', 'kill-session', '-t', 'servmon'], 
                         capture_output=True)
            return True
    except Exception:
        pass
    return False

def main():
    """Main function to generate Argos output"""
    # Get all service statuses
    statuses = get_all_statuses()
    overall_status = get_overall_status(statuses)
    
    # Load previous state
    state_data = load_previous_state()
    previous_statuses = state_data.get('statuses', {})
    degradation_counts = state_data.get('degradation_counts', {})
    
    # Check for degradations with debouncing
    degraded_services, new_degradation_counts = check_status_degradation(
        previous_statuses, statuses, degradation_counts
    )
    
    # If services degraded (after debouncing), launch session
    if degraded_services:
        launch_servmon_session()
    elif overall_status == "operational":
        # All services are operational, kill the session if it exists
        kill_servmon_session()
    
    # Save current state for next check
    save_current_state(statuses, new_degradation_counts)
    
    # Get non-operational services
    non_operational_services = [service for service, status in statuses.items() 
                               if status != "operational"]
    non_operational_count = len(non_operational_services)
    
    # Menu bar display
    if non_operational_count > 0:
        # Create a compact display showing affected services
        if non_operational_count <= 4:
            # Show service emojis for up to 4 services
            service_emojis = []
            for service in non_operational_services:
                # Get emoji for service
                emoji = SERVICE_EMOJIS.get(service, "❓")
                service_emojis.append(emoji)
            
            emojis_str = "".join(service_emojis)
            print(f"{ICONS[overall_status]} {emojis_str}")
        else:
            # Fall back to number if too many
            print(f"{ICONS[overall_status]}{non_operational_count} ☁️")
    else:
        print(f"{ICONS[overall_status]} ☁️")
    print("---")
    
    # Service list in dropdown
    print("Service Health Monitor | size=14")
    print("---")
    
    for service, status in statuses.items():
        icon = ICONS.get(status, ICONS["unknown"])
        service_emoji = SERVICE_EMOJIS.get(service, "❓")
        service_info = SERVICES[service]
        color = ""
        
        if status == "operational":
            color = "color=#2ecc71"
        elif status in ["degraded", "partial"]:
            color = "color=#f39c12"
        elif status in ["major", "critical"]:
            color = "color=#e74c3c"
        else:
            color = "color=#95a5a6"
        
        print(f"{service_emoji} {icon} {service} | href={service_info['status_page']} {color}")
    
    # Refresh and timestamp
    print("---")
    print("🔄 Refresh | refresh=true size=11")
    print(f"Last checked: {datetime.now().strftime('%H:%M:%S')} | size=10 color=#7f8c8d")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Log error to file for debugging
        with open('/tmp/argos-services-error.log', 'w') as f:
            import traceback
            f.write(f"Error at {datetime.now()}: {str(e)}\n")
            f.write(traceback.format_exc())
        # Print minimal output for Argos
        print("⚠️ Error")
        print("---")
        print(f"Script error: {str(e)[:50]}...")
