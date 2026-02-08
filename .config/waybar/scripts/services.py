#!/usr/bin/env python3

import json
import urllib.request
import sys

SERVICES = {
    "AWS": "https://status.aws.amazon.com/data.json",
    "GCP": "https://status.cloud.google.com/incidents.json",
    "Netlify": "https://www.netlifystatus.com/api/v2/status.json",
    "GitHub": "https://www.githubstatus.com/api/v2/status.json",
    "Linear": "https://linearstatus.com/api/v2/status.json",
    "Claude": "https://status.anthropic.com/api/v2/status.json",
    "Quay": "https://status.redhat.com/api/v2/status.json",
    "Rippling": "https://status.rippling.com/api/v2/status.json",
}

ICONS = {"operational": "\u2705", "degraded": "\U0001f7e1", "major": "\U0001f534", "unknown": "\u26aa"}

def check_statuspage(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read())
        if "status" in data:
            ind = data["status"].get("indicator", "none")
            if ind == "none": return "operational"
            if ind == "minor": return "degraded"
            return "major"
    except Exception:
        pass
    return "unknown"

def check_aws(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read())
        if isinstance(data, list):
            for svc in data:
                if isinstance(svc, dict) and svc.get("current") and len(svc["current"]) > 0:
                    return "degraded"
        return "operational"
    except Exception:
        return "operational"

def check_gcp(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read())
        if isinstance(data, list):
            for inc in data:
                if isinstance(inc, dict) and not inc.get("end"):
                    return "degraded"
        return "operational"
    except Exception:
        return "operational"

results = {}
for name, url in SERVICES.items():
    if name == "AWS":
        results[name] = check_aws(url)
    elif name == "GCP":
        results[name] = check_gcp(url)
    else:
        results[name] = check_statuspage(url)

bad = {k: v for k, v in results.items() if v != "operational"}
tooltip = "\n".join(f"{ICONS.get(v, '?')} {k}: {v}" for k, v in results.items())

if bad:
    names = ", ".join(bad.keys())
    text = f"\U0001f7e1 {len(bad)}"
    css_class = "warning"
else:
    text = "\u2705"
    css_class = "normal"

print(json.dumps({"text": text, "tooltip": tooltip, "class": css_class}))
