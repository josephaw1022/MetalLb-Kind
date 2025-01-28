#!/bin/bash

# Get the absolute path to the certificate
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_PATH="$SCRIPT_DIR/.ssl/root-ca.pem"

# Ensure the certificate file exists
if [[ ! -f "$CERT_PATH" ]]; then
  echo "Certificate not found at: $CERT_PATH"
  exit 1
fi


# Launch Chrome and open the certificate settings page
google-chrome "chrome://settings/certificates" &

# Wait for the Chrome window to load
sleep 5

# Find the Chrome window
CHROME_WINDOW=$(xdotool search --sync --onlyvisible --class "chrome" | head -n 1)

if [[ -z "$CHROME_WINDOW" ]]; then
  echo "Failed to detect Chrome window. Ensure Chrome is installed and running."
  exit 1
fi

# Activate the Chrome window
xdotool windowactivate "$CHROME_WINDOW"

# Simulate navigating to the "Authorities" tab
sleep 2
xdotool key Tab Tab Tab Tab Tab Tab Return # Adjust the number of Tab presses if needed

# Simulate clicking the "Import" button
sleep 2
xdotool mousemove --sync 300 400 click 1 # Adjust coordinates based on your screen resolution

# Enter the certificate path in the file selection dialog
sleep 2
xdotool type "$CERT_PATH"
xdotool key Return

# Simulate selecting "Trust this certificate for identifying websites"
sleep 2
xdotool key space
xdotool key Return

echo "Certificate imported successfully!"

