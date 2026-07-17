#!/usr/bin/env python3

# Enhanced Weather for Argos
# Shows current weather and 5-day forecast with rich details

import json
import subprocess
from urllib.request import urlopen
from urllib.error import URLError, HTTPError
from urllib.parse import quote
import datetime

# Configuration
location_name = "Mittelbuchen"
pass_entry = "personal/WEATHER_API_KEY"
units = 'metric'  # kelvin, metric, imperial
lang = 'en'

# Weather icon mapping
weather_icons = {
    # Thunderstorm
    200: "⛈", 201: "⛈", 202: "⛈", 210: "🌩", 211: "🌩", 212: "🌩", 221: "🌩", 230: "⛈", 231: "⛈", 232: "⛈",
    # Drizzle
    300: "🌦", 301: "🌦", 302: "🌦", 310: "🌦", 311: "🌦", 312: "🌦", 313: "🌦", 314: "🌦", 321: "🌦",
    # Rain
    500: "🌦", 501: "🌧", 502: "🌧", 503: "🌧", 504: "🌧", 511: "🌨", 520: "🌧", 521: "🌧", 522: "🌧", 531: "🌧",
    # Snow
    600: "🌨", 601: "🌨", 602: "❄️", 611: "🌨", 612: "🌨", 613: "🌨", 615: "🌨", 616: "🌨", 620: "🌨", 621: "❄️", 622: "❄️",
    # Atmosphere
    701: "🌫", 711: "🌫", 721: "🌫", 731: "🌫", 741: "🌫", 751: "🌫", 761: "🌫", 762: "🌫", 771: "🌫", 781: "🌪",
    # Clear
    800: "☀️",
    # Clouds
    801: "🌤", 802: "⛅", 803: "🌥", 804: "☁️"
}

def get_weather_icon(weather_id):
    return weather_icons.get(weather_id, "🌡")

def format_time(timestamp):
    return datetime.datetime.fromtimestamp(timestamp).strftime('%H:%M')

def format_day(timestamp):
    return datetime.datetime.fromtimestamp(timestamp).strftime('%a')

def get_wind_direction(degrees):
    directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    index = round(degrees / 22.5) % 16
    return directions[index]

def get_api_key():
    result = subprocess.run(["pass", "show", pass_entry], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"pass show {pass_entry}: {result.stderr.strip() or 'failed'}")
    key = result.stdout.strip()
    if not key:
        raise RuntimeError(f"pass entry {pass_entry} is empty")
    return key

def fetch(endpoint, api_key):
    url = f'https://api.openweathermap.org/data/2.5/{endpoint}?q={quote(location_name)}&units={units}&lang={lang}&appid={api_key}'
    # Build the message from code/reason only, and cut the cause chain: the URL
    # carries the key and must never reach the panel or a traceback.
    try:
        return json.load(urlopen(url, timeout=15))
    except HTTPError as e:
        raise RuntimeError(f"{endpoint}: HTTP {e.code} {e.reason}") from None
    except URLError as e:
        raise RuntimeError(f"{endpoint}: {e.reason}") from None

def get_weather_data():
    api_key = get_api_key()
    return {
        'current': fetch('weather', api_key),
        'forecast': fetch('forecast', api_key)
    }

def format_weather():
    try:
        data = get_weather_data()
    except Exception as e:
        return f"⚠️ Weather\n---\n{e} | color=red size=11\n---\n🔄 Refresh | refresh=true size=11\n"

    current = data['current']
    forecast = data['forecast']
    
    # Temperature unit
    temp_unit = {'metric': '°C', 'imperial': '°F', 'kelvin': 'K'}[units]
    speed_unit = {'metric': 'm/s', 'imperial': 'mph', 'kelvin': 'm/s'}[units]
    
    # Current weather
    temp = round(current['main']['temp'])
    feels_like = round(current['main']['feels_like'])
    icon = get_weather_icon(current['weather'][0]['id'])
    description = current['weather'][0]['description'].title()
    
    # Menu bar display (pango markup for consistent font/color, avoid ° which breaks pango)
    output = f"<tt><b>{icon}</b></tt><tt><span color='#87ceeb'>{temp}C</span></tt> | font='monospace' size=12 dropdown=false\n"
    output += "---\n"
    
    # Current conditions header
    output += f"📍 {current['name']}, {current['sys']['country']} | size=14\n"
    output += f"{description} | size=12\n"
    output += "---\n"
    
    # Temperature details
    output += f"🌡 Temperature: {temp}{temp_unit} (feels like {feels_like}{temp_unit}) | color=#ff6b6b\n"
    output += f"↑ High: {round(current['main']['temp_max'])}{temp_unit}  ↓ Low: {round(current['main']['temp_min'])}{temp_unit} | size=11\n"
    output += "---\n"
    
    # Additional details
    output += f"💧 Humidity: {current['main']['humidity']}% | color=#4ecdc4\n"
    output += f"💨 Wind: {current['wind']['speed']} {speed_unit} {get_wind_direction(current['wind'].get('deg', 0))} | color=#95e1d3\n"
    output += f"🔵 Pressure: {current['main']['pressure']} hPa | color=#74b9ff\n"
    output += f"👁 Visibility: {current['visibility']/1000:.1f} km | color=#a29bfe\n"
    
    if 'clouds' in current:
        output += f"☁️ Cloudiness: {current['clouds']['all']}% | color=#dfe6e9\n"
    
    # Sunrise/Sunset
    output += "---\n"
    sunrise = format_time(current['sys']['sunrise'])
    sunset = format_time(current['sys']['sunset'])
    output += f"🌅 Sunrise: {sunrise}  🌇 Sunset: {sunset} | color=#f39c12\n"
    
    # 5-day forecast
    output += "---\n"
    output += "📅 5-Day Forecast | size=13\n"
    output += "---\n"
    
    # Group forecast by day
    daily_forecasts = {}
    for item in forecast['list'][:40]:  # Next 5 days
        day = datetime.datetime.fromtimestamp(item['dt']).strftime('%Y-%m-%d')
        if day not in daily_forecasts:
            daily_forecasts[day] = []
        daily_forecasts[day].append(item)
    
    # Display daily summary
    for day, items in list(daily_forecasts.items())[:5]:
        # Calculate daily min/max
        temps = [item['main']['temp'] for item in items]
        min_temp = round(min(temps))
        max_temp = round(max(temps))
        
        # Get most common weather condition
        weather_ids = [item['weather'][0]['id'] for item in items]
        most_common_id = max(set(weather_ids), key=weather_ids.count)
        day_icon = get_weather_icon(most_common_id)
        
        # Format day
        day_name = format_day(items[0]['dt'])
        date = datetime.datetime.fromtimestamp(items[0]['dt']).strftime('%m/%d')
        
        output += f"{day_icon} {day_name} {date}: {max_temp}{temp_unit}/{min_temp}{temp_unit} | font=Menlo\n"
    
    # Refresh and update time
    output += "---\n"
    update_time = datetime.datetime.now().strftime('%H:%M:%S')
    output += f"🔄 Refresh | refresh=true size=11\n"
    output += f"Last updated: {update_time} | size=10 color=#636e72\n"
    
    return output

# Main execution
print(format_weather())
