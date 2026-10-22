#!/usr/bin/env python3

# Service Status Monitor for Argos
# Monitors AWS, GCP, Azure, Netlify, Cloudflare, GitHub, Linear, Claude,
# OpenAI, Rippling, Spacelift, and Tailscale status pages

import json
import urllib.request
import urllib.error
from datetime import datetime
import os
import base64
import tempfile
import hashlib

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
    "Cloudflare": {
        # Cloudflare's top-level status.indicator reads "minor" almost
        # chronically from per-PoP component chatter (edge datacenters in
        # partial_outage/under_maintenance) even when the board shows "All
        # Systems Operational". Key off posted (unresolved) incidents instead,
        # so we only flag a real, board-level Cloudflare incident. Click-through
        # opens the new status page UI.
        "api": "https://www.cloudflarestatus.com/api/v2/incidents/unresolved.json",
        "status_page": "https://new.cloudflarestatus.com/",
        "name": "Cloudflare",
        "favicon": "https://www.cloudflare.com/favicon.ico"
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
    "Claude": {
        "api": "https://status.anthropic.com/api/v2/status.json",
        "status_page": "https://status.anthropic.com/",
        "name": "Claude",
        "favicon": "https://claude.ai/favicon.ico"
    },
    "OpenAI": {
        "api": "https://status.openai.com/api/v2/status.json",
        "status_page": "https://status.openai.com/",
        "name": "OpenAI",
        # openai.com and chatgpt.com both 403 the favicon to a scripted UA;
        # the status page serves its own.
        "favicon": "https://status.openai.com/favicon.ico"
    },
    "Rippling": {
        "api": "https://status.rippling.com/api/v2/status.json",
        "status_page": "https://status.rippling.com/",
        "name": "Rippling",
        "favicon": "https://www.rippling.com/favicon.ico"
    },
    "Spacelift": {
        "api": "https://spacelift.statuspage.io/api/v2/status.json",
        "status_page": "https://spacelift.statuspage.io/",
        "name": "Spacelift",
        "favicon": "https://spacelift.io/favicons/favicon-32x32.png"
    },
    "Tailscale": {
        "api": "https://status.tailscale.com/api/v2/status.json",
        "status_page": "https://status.tailscale.com/",
        "name": "Tailscale",
        "favicon": "https://status.tailscale.com/favicon.ico"
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
    "Cloudflare": "🌐", # Globe for Cloudflare (avoid orange/yellow: reads as a status light)
    "GitHub": "🐙",   # Octopus (Octocat) for GitHub
    "Linear": "📋",   # Clipboard for Linear issues
    "Claude": "🤖",   # Robot for AI
    "OpenAI": "🌀",   # Spiral for the OpenAI knot mark (blue, not a status colour)
    "Rippling": "💼", # Briefcase for HR/workforce management
    "Spacelift": "🛰️", # Satellite for Spacelift IaC orchestration
    "Tailscale": "🔗"   # Link for the Tailscale mesh network
}

# Cache directory for favicons
CACHE_DIR = os.path.join(tempfile.gettempdir(), 'argos-favicons')
os.makedirs(CACHE_DIR, exist_ok=True)

# State file for tracking status changes
STATE_DIR = os.path.join(os.path.expanduser('~'), '.local', 'state', 'argos-service-monitor')
os.makedirs(STATE_DIR, exist_ok=True)
STATE_FILE = os.path.join(STATE_DIR, 'services_status_state.json')

# Providers whose feed failed this run. The board still shows its default
# status for them, but the Gordon notifier ignores them (no transition).
FEED_ERRORS = set()

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
            FEED_ERRORS.add("AWS")
            # Try simpler health check endpoint = "https://health.aws.amazon.com/health/status"
            req = urllib.request.Request(health_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    return "operational"
    except Exception:
        FEED_ERRORS.add("AWS")
    return "operational"  # Default to operational for AWS

def gcp_active_incidents(data):
    """Return the GCP incidents that have no 'end' (still active)."""
    if not isinstance(data, list):
        return []
    return [i for i in data if isinstance(i, dict) and not i.get('end', None)]

def get_gcp_status():
    """Check GCP status"""
    try:
        data = fetch_status(SERVICES["GCP"]["api"])
        if data and isinstance(data, list):
            # Check only for active/ongoing incidents
            return "degraded" if gcp_active_incidents(data) else "operational"
        # No feed: the board keeps showing operational, but the Gordon
        # notifier must not read this as a recovery.
        FEED_ERRORS.add("GCP")
        return "operational"
    except Exception:
        pass
    FEED_ERRORS.add("GCP")
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

def get_cloudflare_status():
    """Cloudflare status from posted (unresolved) incidents, NOT the top-level
    indicator. Cloudflare's overall indicator sits at "minor" almost chronically
    from per-PoP component partial-outages/maintenance even when the board reads
    "All Systems Operational", so keying off it cries wolf. We flag only on a
    real incident on the board:
      major/critical incident -> major   (red: it's down)
      minor incident          -> degraded (yellow: click to see what's affected)
      no incident             -> operational (green)
    Maintenance is not an outage and is excluded (unresolved.json is incidents
    only; any 'maintenance'/'none' impact also maps to operational)."""
    try:
        data = fetch_status(SERVICES["Cloudflare"]["api"])
        if data is None:
            return "unknown"
        impacts = {inc.get('impact', 'none') for inc in data.get('incidents', [])}
        if impacts & {'major', 'critical'}:
            return "major"
        if 'minor' in impacts:
            return "degraded"
        return "operational"
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

def get_rippling_status():
    """Check Rippling status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Rippling"]["api"])
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

def get_openai_status():
    """Check OpenAI status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["OpenAI"]["api"])
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

def get_spacelift_status():
    """Check Spacelift status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Spacelift"]["api"])
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

def get_tailscale_status():
    """Check Tailscale status using statuspage.io API"""
    try:
        data = fetch_status(SERVICES["Tailscale"]["api"])
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
        "Cloudflare": get_cloudflare_status(),
        "GitHub": get_github_status(),
        "Linear": get_linear_status(),
        "Claude": get_claude_status(),
        "OpenAI": get_openai_status(),
        "Rippling": get_rippling_status(),
        "Spacelift": get_spacelift_status(),
        "Tailscale": get_tailscale_status()
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


# ---- Kendra notifications ---------------------------------------------------
# Kendra (Gordon while she is down) reads ~/.local/state/notifications.log
# through notify-watch (same record format as __reminder.sh notify_gordon):
# "date time<TAB>app<TAB>summary<TAB>body". One line per provider change,
# never per run: a move between operational, degraded and major, and, while a
# provider is not operational, a change in its posted incidents or affected
# components. Components come from the statuspage components feed, except
# Cloudflare's, whose ~480 per-PoP components churn without an incident.
# Env overrides (tests): ARGOS_NOTIFY_LOG, ARGOS_STATE_DIR.

GORDON_STATE_NAME = 'gordon_notified_state.json'

def notify_log_path():
    """Path of the notifications log Gordon watches."""
    override = os.environ.get('ARGOS_NOTIFY_LOG')
    if override:
        return override
    base = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'state')
    return os.path.join(base, 'notifications.log')

def _one_line(text):
    return ' '.join(str(text).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').split())

def append_gordon_line(summary, body):
    """Append one record to the log. A single O_APPEND write, capped under
    PIPE_BUF, so it cannot interleave with other writers. True on success."""
    summary = _one_line(summary)[:300]
    body = _one_line(body).encode('utf-8')[:3000].decode('utf-8', 'ignore')
    line = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\targos\t{summary}\t{body}\n"
    try:
        fd = os.open(notify_log_path(), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            os.write(fd, line.encode('utf-8'))
        finally:
            os.close(fd)
        return True
    except OSError:
        return False

def _status_dir():
    return os.environ.get('ARGOS_STATE_DIR') or STATE_DIR

def _join(items, limit):
    items = [i for i in items if i]
    shown = ', '.join(items[:limit])
    return shown + (f" (+{len(items) - limit} more)" if len(items) > limit else '')

def describe_gcp(data):
    """(title, impacted) for the active GCP incidents in the incidents feed."""
    active = gcp_active_incidents(data)
    if not active:
        return None, ''
    active.sort(key=lambda i: i.get('begin') or '', reverse=True)
    title = active[0].get('external_desc') or active[0].get('service_name') or 'incident'
    locations, products = [], []
    for inc in active:
        recent = inc.get('most_recent_update') or {}
        for loc in (recent.get('affected_locations') or inc.get('currently_affected_locations') or []):
            name = loc.get('title') or loc.get('id') if isinstance(loc, dict) else None
            if name and name not in locations:
                locations.append(name)
        for prod in inc.get('affected_products') or []:
            name = prod.get('title') if isinstance(prod, dict) else None
            if name and name not in products:
                products.append(name)
    parts = []
    if len(active) > 1:
        parts.append(f"{len(active)} active incidents")
    if locations:
        parts.append("regions: " + _join(locations, 8))
    if products:
        parts.append("products: " + _join(products, 8))
    return title, '; '.join(parts)

def describe_statuspage(url):
    """(title, impacted) from a statuspage.io unresolved incidents feed."""
    data = fetch_status(url) if url else None
    incidents = (data or {}).get('incidents') or []
    if not incidents:
        return None, ''
    title = incidents[0].get('name') or 'incident'
    components = []
    for inc in incidents:
        for comp in inc.get('components') or []:
            if comp.get('name') and comp['name'] not in components:
                components.append(comp['name'])
    return title, ("components: " + _join(components, 8)) if components else ''

def describe_outage(service):
    """Best-effort (title, impacted) for a provider that just went down."""
    try:
        api = SERVICES[service]['api']
        if service == 'GCP':
            title, impacted = describe_gcp(fetch_status(api))
        elif api.endswith('/status.json'):
            title, impacted = describe_statuspage(api[:-len('status.json')] + 'incidents/unresolved.json')
        elif api.endswith('/incidents/unresolved.json'):
            title, impacted = describe_statuspage(api)
        else:
            title, impacted = None, ''
    except Exception:
        title, impacted = None, ''
    return title or 'status page reports an outage', impacted

# Statuspage component states worth a line; maintenance is not an incident.
COMPONENT_WORDS = {
    'degraded_performance': 'degraded',
    'partial_outage': 'partial outage',
    'major_outage': 'major outage',
}
# Providers whose components feed is per-PoP noise.
NO_COMPONENTS = {'Cloudflare'}

def statuspage_base(service):
    """The statuspage.io API base (".../api/v2/") of a provider, or None."""
    api = SERVICES[service]['api']
    for tail in ('status.json', 'incidents/unresolved.json'):
        if api.endswith('/api/v2/' + tail):
            return api[:-len(tail)]
    return None

def details(service):
    """(incidents, components) a provider's status page posts now: incident
    names, and {component: state} for affected components. None when a feed
    could not be read, so a fetch failure never reads as a change."""
    if service == 'GCP':
        data = fetch_status(SERVICES['GCP']['api'])
        if not isinstance(data, list):
            return None
        active = gcp_active_incidents(data)
        incidents = sorted({i.get('external_desc') or i.get('service_name') or 'incident' for i in active})
        components = {}
        for inc in active:
            for prod in inc.get('affected_products') or []:
                if isinstance(prod, dict) and prod.get('title'):
                    components[prod['title']] = 'affected'
        return incidents, components
    base = statuspage_base(service)
    if base is None:
        return [], {}
    data = fetch_status(base + 'incidents/unresolved.json')
    if not isinstance(data, dict):
        return None
    incidents = sorted({i.get('name') or 'incident' for i in data.get('incidents') or []})
    components = {}
    if service not in NO_COMPONENTS:
        feed = fetch_status(base + 'components.json')
        if not isinstance(feed, dict):
            return None
        for comp in feed.get('components') or []:
            word = COMPONENT_WORDS.get(comp.get('status'))
            if word and comp.get('name') and not comp.get('group'):
                components[comp['name']] = word
    return incidents, components

def _changes(old, new_incidents, new_components):
    """What moved between two snapshots, as short phrases."""
    out = []
    old_inc = set(old.get('incidents') or [])
    old_comp = old.get('components') or {}
    out += [f"new incident: {i}" for i in new_incidents if i not in old_inc]
    out += [f"resolved: {i}" for i in sorted(old_inc - set(new_incidents))]
    for name, word in sorted(new_components.items()):
        if name not in old_comp:
            out.append(f"+{name} ({word})")
        elif old_comp[name] != word:
            out.append(f"{name} {old_comp[name]} -> {word}")
    out += [f"-{name}" for name in sorted(set(old_comp) - set(new_components))]
    return out

def notify_transitions(statuses):
    """Append one Kendra line per provider whose level, posted incidents or
    affected components changed since the last run. The first run (no state
    file), any provider seen for the first time, and an outage recorded by the
    older two-state notifier are recorded without a line. State is written
    atomically, after the append, so a failed append is retried next run
    instead of lost."""
    state_path = os.path.join(_status_dir(), GORDON_STATE_NAME)
    prev = None
    try:
        with open(state_path) as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            prev = loaded
    except (OSError, ValueError):
        prev = None
    new = dict(prev or {})
    for service, status in statuses.items():
        # A failed or unreadable feed is not an observation.
        if service in FEED_ERRORS or status == "unknown":
            continue
        level = "operational" if status == "operational" else ("major" if status in ("major", "critical") else "degraded")
        old = new.get(service)
        known = isinstance(old, dict) and old.get('state') in ("operational", "degraded", "major", "outage")
        info = SERVICES[service]
        if level == "operational":
            if known and old['state'] == "operational":
                continue
            entry = {'state': 'operational'}
            if not known:
                new[service] = entry
                continue
            summary = f"{service} recovered"
            body = f"Provider: {info['name']}. State: operational."
            if old.get('title'):
                body += f" Was: {old['title']}."
        else:
            got = details(service)
            if got is None:
                # Keep the last known incidents and components.
                got = ((old or {}).get('incidents') or [], (old or {}).get('components') or {}) if known else ([], {})
            incidents, components = got
            title, impacted = describe_outage(service)
            entry = {'state': level, 'title': title, 'incidents': incidents, 'components': components}
            if not known or old['state'] == "outage":
                new[service] = entry
                continue
            word = "outage" if level == "major" else "degraded"
            if old['state'] == "operational":
                summary = f"{service} {word}: {title}"
            elif old['state'] != level:
                summary = f"{service} now {word}: {title}"
            else:
                moved = _changes(old, incidents, components)
                if not moved:
                    continue
                summary = f"{service} update: {title}"
            body = f"Provider: {info['name']}. State: {status}."
            if old['state'] == level:
                body += f" Changed: {'; '.join(_changes(old, incidents, components))}."
            if components and service != 'GCP':
                body += " Components: " + _join([f"{n} ({w})" for n, w in sorted(components.items())], 12) + "."
            elif impacted:
                body += f" Impacted {impacted}."
        body += f" Status: {info['status_page']}"
        if append_gordon_line(summary, body):
            new[service] = entry
    if new != prev:
        try:
            os.makedirs(_status_dir(), exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=_status_dir(), prefix='.gordon-state-')
            with os.fdopen(fd, 'w') as f:
                json.dump(new, f, indent=2)
            os.replace(tmp, state_path)
        except OSError:
            pass

# Removed launch_servmon_session and kill_servmon_session functions
# These are no longer needed as we don't want to create tmux sessions

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
    
    # Tell Gordon about transitions; never let it break the board
    try:
        notify_transitions(statuses)
    except Exception:
        pass

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
