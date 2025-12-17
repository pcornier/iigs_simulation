#!/bin/bash
# Fetch Apple IIgs Technical Notes from apple2.gs
# Downloads TN.IIGS.001.txt through TN.IIGS.101.txt

BASE_URL="https://apple2.gs/technotes/tn/iigs"

echo "Fetching Apple IIgs Technical Notes..."

for i in $(seq 1 101); do
    # Format number with leading zeros (001, 002, ..., 101)
    NUM=$(printf "%03d" $i)
    FILENAME="TN.IIGS.${NUM}.txt"
    URL="${BASE_URL}/${FILENAME}"

    echo "Downloading ${FILENAME}..."
    curl -k -s -o "${FILENAME}" "${URL}"

    # Check if download was successful (file exists and has content)
    if [ -s "${FILENAME}" ]; then
        echo "  OK"
    else
        echo "  Not found or empty"
        rm -f "${FILENAME}"
    fi
done

echo "Done!"
