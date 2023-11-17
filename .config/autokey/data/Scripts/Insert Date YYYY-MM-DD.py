import subprocess
from datetime import datetime

# Executing the 'date' command and getting the output
output = subprocess.check_output("date").decode('utf-8').strip()

# Parsing the output into a datetime object
date_object = datetime.strptime(output, '%a %d %b %H:%M:%S %Z %Y')

# Formatting the date in 'YYYY-MM-DD' format
formatted_date = date_object.strftime('%Y-%m-%d')

# Sending the formatted date as keyboard input
keyboard.send_keys(formatted_date)