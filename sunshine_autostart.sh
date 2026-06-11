#!/bin/bash

# Function to check if KDE has fully started
kde_started() {
    pgrep -x "kded6" > /dev/null
}

# Timeout period in seconds
TIMEOUT=300
INTERVAL=10
elapsed=0

# Wait until KDE has started or timeout is reached
while ! kde_started; do
    if [ $elapsed -ge $TIMEOUT ]; then
        echo "Timeout reached. KDE did not start."
        exit 1
    fi
    echo "KDE not started yet. Checking again in $INTERVAL seconds..."
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

echo "KDE started. Sleep for 60 seconds..."
sleep 60

echo "Starting the application..."
# Start the application
sunshine
