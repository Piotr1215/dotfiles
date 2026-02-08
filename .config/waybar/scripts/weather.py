#!/usr/bin/env python3

import json
from urllib.request import urlopen
from urllib.parse import quote

LOCATION = "Mittelbuchen"
API_KEY = "4352a9de435f84cf435c03bd62073747"

ICONS = {
    200: "\u26c8", 300: "\U0001f326", 500: "\U0001f326", 501: "\U0001f327",
    600: "\U0001f328", 602: "\u2744\ufe0f", 701: "\U0001f32b", 781: "\U0001f32a",
    800: "\u2600\ufe0f", 801: "\U0001f324", 802: "\u26c5", 803: "\U0001f325", 804: "\u2601\ufe0f"
}

def icon(wid):
    for k in sorted(ICONS.keys(), reverse=True):
        if wid >= k:
            return ICONS[k]
    return "\U0001f321"

try:
    url = f"https://api.openweathermap.org/data/2.5/weather?q={quote(LOCATION)}&units=metric&appid={API_KEY}"
    data = json.load(urlopen(url, timeout=5))
    temp = round(data["main"]["temp"])
    wicon = icon(data["weather"][0]["id"])
    desc = data["weather"][0]["description"].title()
    feels = round(data["main"]["feels_like"])
    hum = data["main"]["humidity"]
    wind = data["wind"]["speed"]
    text = f"{wicon} {temp}\u00b0C"
    tooltip = f"{desc}\nFeels like {feels}\u00b0C\nHumidity {hum}%\nWind {wind} m/s"
    print(json.dumps({"text": text, "tooltip": tooltip}))
except Exception as e:
    print(json.dumps({"text": "\u26a0 Weather", "tooltip": str(e)}))
