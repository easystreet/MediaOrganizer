#!/bin/bash
start_dir="$1"
# Initialize an empty array to hold the scores for each video
scores=()

# Loop through each MP4 file in the current directory and all subdirectories
while IFS= read -r -d '' file; do
    # Check if the file is in a "low quality" folder
    if [[ $(basename "$(dirname "$file")") =~ ^(low quality|Low Quality)$ ]]; then
        continue
    fi

    echo "Processing..."

    # Extract the bitrate, filesize, duration, resolution, and framerate using ffprobe
    bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file")
    filesize=$(stat -c %s "$file")
    duration=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$file" | awk -F. '{print $1}')
    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$file")
    height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file")
    framerate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$file" | awk -F/ '{printf "%.2f", $1 / $2}')

    # Calculate the score based on the bitrate, filesize, and duration
    if (( duration > 0 )) && (( filesize > 0 )); then
        score=$((bitrate*duration*1000/filesize))
    else
        score=0
    fi

# Assess the video quality based on the resolution and framerate
quality=0
if (( width >= 3840 && height >= 2160 )) && (awk -v fps="$framerate" 'BEGIN {exit !(fps >= 50)}'); then
    quality=5
elif (( width >= 1920 && height >= 1080 )) && (awk -v fps="$framerate" 'BEGIN {exit !(fps >= 23)}'); then
    quality=4
elif (( width >= 1280 && height >= 720 )) && (awk -v fps="$framerate" 'BEGIN {exit !(fps >= 23)}'); then
    quality=3
elif (( width >= 854 && height >= 480 )) && (awk -v fps="$framerate" 'BEGIN {exit !(fps >= 23)}'); then
    quality=2
else
    quality=1
fi

    # Print out the video information, score, and quality
    printf "%skbps, size=%sB, duration=%ss, score=%skbps, resolution=%sx%s, framerate=%.2f, quality=%s\n" "$bitrate" "$filesize" "$duration" "$score" "$width" "$height" "$framerate" "$quality"

    # Add the score to the scores array
    scores+=("$score:$quality:$file")
done < <(find "$start_dir" -type f -name "*.mp4" -print0)


# Calculate the average score and quality for all the videos
total_score=0
total_quality=0
for score in "${scores[@]}"; do
    # Extract the score, quality, and file path from the score string
    score_val=$(echo "$score" | cut -d':' -f1)
    quality_val=$(echo "$score" | cut -d':' -f2)
    file_path=$(echo "$score" | cut -d':' -f3)

    # Add the score and quality to the running totals
    total_score=$((total_score + score_val))
    total_quality=$((total_quality + quality_val))
done
num_scores=${#scores[@]}
if (( num_scores > 0 )); then
    average_score=$((total_score / num_scores))
    average_quality=$((total_quality / num_scores))
    printf "\nAverage score: %.2fkbps\n" "$average_score"

    # Sort the scores array by ascending score, quality, and filename
    IFS=$'\n'
    sorted_scores=($(printf "%s\n" "${scores[@]}" | sort -t: -k1,1n -k2,2n -k3,3))

    # Only show the lowest quality videos that should be moved to archive
    printf "\nVideos to move to archive being logged.\n"
    for score in "${sorted_scores[@]}"; do
        # Extract the score, quality, and file path from the score string
        score_val=$(echo "$score" | cut -d':' -f1)
        quality_val=$(echo "$score" | cut -d':' -f2)
        file_path=$(echo "$score" | cut -d':' -f3)

        # Only show videos with a quality score of 1 or lower
        if ((quality_val <= 1)); then
            # Check if a "low quality" folder exists
            low_quality_folder=$(dirname "$file_path")/"low quality"
            if [ -d "$low_quality_folder" ] || [ -d "$(dirname "$file_path")/Low Quality" ]; then
                # Move the file to the "low quality" folder
                mv "$file_path" "$low_quality_folder"/
                printf "Moved file: %s to %s\n" "$file_path" "$low_quality_folder"
            else
                # Get the video information and print it
                bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_path")
                filesize=$(stat -c %s "$file_path")
                duration=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" | awk -F. '{print $1}')
                resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 "$file_path")
                framerate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" | awk -F/ '{printf "%.2f", $1 / $2}')

                printf "%skbps, %sB, duration=%ss, score=%skbps, resolution=%sx%s, framerate=%.2f, quality=%s\n" "$bitrate" "$filesize" "$duration" "$score" "$width" "$height" "$framerate" "$quality"
            fi
        fi
    done > output.txt
fi

