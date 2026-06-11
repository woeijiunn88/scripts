# Specify one folder to convert png to jpg, png file will be deleted

#!/bin/bash

target_dir="$1"
max_jobs=24   # number of images processed concurrently

# Count PNG files for progress
total=$(find "$target_dir" -type f -iname '*.png' | wc -l)
count=0

# Function to convert one image
convert_one() {
    local f="$1"
    local idx="$2"
    local total="$3"

    echo "[$idx / $total] Converting: $f"
    jpg="${f%.png}.jpg"

    if magick "$f" -quality 90 "$jpg"; then
        touch -r "$f" "$jpg"   # keep modified time
        rm "$f"
    fi
}

# Export function so subshells can see it
export -f convert_one

# Export total for use in background jobs
export total

# Semaphore function to limit concurrent jobs
sem() {
    local max=$1
    while (( $(jobs -rp | wc -l) >= max )); do
        sleep 0.1
    done
}

# Process images
while IFS= read -r f; do
    count=$((count + 1))
    sem "$max_jobs"  # wait if too many jobs
    convert_one "$f" "$count" "$total" &
done < <(find "$target_dir" -type f -iname '*.png')

# Wait for all background jobs to finish
wait

echo "Done."
