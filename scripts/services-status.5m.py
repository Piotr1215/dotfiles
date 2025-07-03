#!/usr/bin/env python3

# Service Status Monitor for Argos
# Monitors AWS, GCP, Azure, Netlify, GitHub, Linear, and GoDaddy status pages

import json
import urllib.request
import urllib.error
from datetime import datetime

# Service configurations with status page URLs
SERVICES = {
    "AWS": {
        "api": "https://status.aws.amazon.com/data.json",
        "status_page": "https://status.aws.amazon.com/",
        "name": "Amazon Web Services"
    },
    "GCP": {
        "api": "https://status.cloud.google.com/incidents.json",
        "status_page": "https://status.cloud.google.com/",
        "name": "Google Cloud Platform"
    },
    "Azure": {
        "api": "https://status.azure.com/en-us/status/feed/",
        "status_page": "https://status.azure.com/en-us/status",
        "name": "Microsoft Azure"
    },
    "Netlify": {
        "api": "https://www.netlifystatus.com/api/v2/status.json",
        "status_page": "https://www.netlifystatus.com/",
        "name": "Netlify"
    },
    "GitHub": {
        "api": "https://www.githubstatus.com/api/v2/status.json",
        "status_page": "https://www.githubstatus.com/",
        "name": "GitHub"
    },
    "Linear": {
        "api": "https://linearstatus.com/api/v2/status.json",
        "status_page": "https://linearstatus.com/",
        "name": "Linear"
    },
    "GoDaddy": {
        "api": "https://status.godaddy.com/api/v2/status.json",
        "status_page": "https://status.godaddy.com/",
        "name": "GoDaddy"
    },
    "Claude": {
        "api": "https://status.anthropic.com/api/v2/status.json",
        "status_page": "https://status.anthropic.com/",
        "name": "Claude"
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
    except:
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
    except:
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
    except:
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
    except:
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
    except:
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
    except:
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
    except:
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
    except:
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
        "Claude": get_claude_status()
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

def main():
    """Main function to generate Argos output"""
    # Get all service statuses
    statuses = get_all_statuses()
    overall_status = get_overall_status(statuses)
    
    # Menu bar icon
    print(f"{ICONS[overall_status]} ☁️")
    print("---")
    
    # Service list in dropdown
    print("Service Health Monitor | size=14")
    print("---")
    
    for service, status in statuses.items():
        icon = ICONS.get(status, ICONS["unknown"])
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
        
        print(f"{icon} {service} | href={service_info['status_page']} {color}")
    
    # Refresh and timestamp
    print("---")
    print("🔄 Refresh | refresh=true size=11")
    print(f"Last checked: {datetime.now().strftime('%H:%M:%S')} | size=10 color=#7f8c8d")

if __name__ == "__main__":
    main()
