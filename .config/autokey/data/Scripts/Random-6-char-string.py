import random
import string

# Create the character pool - using letters and digits
chars = string.ascii_letters + string.digits

# Generate a 6-character random string
random_string = ''.join(random.choice(chars) for _ in range(6))

# Send the random string via keyboard
keyboard.send_keys(random_string)
