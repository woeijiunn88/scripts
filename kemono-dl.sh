#!/bin/bash

# Check if at least one link is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <link1> [<link2> ... <linkN>]"
    exit 1
fi

# Define the cookies file and output directory
COOKIES_FILE="/home/woeijiunn88/.local/share/kemono-dl/cookies.txt"

# Count the number of links
NUM_LINKS="$#"
echo "Number of links provided: $NUM_LINKS"

# Echo message about skipped file types
echo "Skipping files of type: psd, clip"

# Loop through all the provided links
for LINK in "$@"
do
    echo "Processing link: $LINK"
    python /home/woeijiunn88/.local/share/kemono-dl/kemono-dl.py --cookies "$COOKIES_FILE" --links "$LINK" --skip-filetype "" --post-timeout 0 --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:97.0) Gecko/20100101 Firefox/97.0"
    NUM_LINKS=$((NUM_LINKS-1))
    echo "Remaining links to process: $NUM_LINKS"
done

echo "All downloads are complete."
