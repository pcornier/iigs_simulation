#!/bin/bash

# --- Configuration ---
# 1. Set this variable to the directory you want to search.
TARGET_DIR="./65816/v1/"

# 2. Set this variable to the program you want to run.
#    (e.g., "./my_program", "python my_script.py", "echo", etc.)
PROGRAM_TO_RUN="./obj_dir/Vsinglesteptests"
# --- End Configuration ---

# Check if the target directory is set and exists
if [ -z "$TARGET_DIR" ]; then
    echo "Error: TARGET_DIR is not set. Please edit the script."
    exit 1
elif [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' not found."
    exit 1
fi

# Check if the program is set
if [ -z "$PROGRAM_TO_RUN" ]; then
    echo "Error: PROGRAM_TO_RUN is not set. Please edit the script."
    exit 1
fi

echo "Searching for files in: $TARGET_DIR"
echo "Running program: $PROGRAM_TO_RUN"
echo "---"

# Use 'find' to locate all files (-type f) in the target directory.
# The 'while read -r file' loop processes each file path safely,
# even if file names contain spaces.
find "$TARGET_DIR" -type f | sort  | while read -r file
do
    echo "Processing file: $file"
    
    # Call your program with the file as the first argument
    "$PROGRAM_TO_RUN" "$file"
    
    # Optional: Add a small separator for readability
    # echo "---"
done

echo "---"
echo "Script finished." 
