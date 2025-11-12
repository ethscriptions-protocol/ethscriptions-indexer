#!/bin/bash

# Script to compress collection JSON files into a single tar.gz archive

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

ITEMS_FILE="items_by_ethscription.json"
COLLECTIONS_FILE="collections_by_name.json"
ARCHIVE_FILE="collections_data.tar.gz"

# Check if JSON files exist
if [ ! -f "$ITEMS_FILE" ]; then
    echo "Error: $ITEMS_FILE not found!"
    exit 1
fi

if [ ! -f "$COLLECTIONS_FILE" ]; then
    echo "Error: $COLLECTIONS_FILE not found!"
    exit 1
fi

# Create tar.gz archive
echo "Creating $ARCHIVE_FILE..."
tar -czf "$ARCHIVE_FILE" "$ITEMS_FILE" "$COLLECTIONS_FILE"

if [ $? -eq 0 ]; then
    echo "Successfully created $ARCHIVE_FILE"

    # Show file sizes for comparison
    echo ""
    echo "File sizes:"
    ls -lh "$ITEMS_FILE" "$COLLECTIONS_FILE" "$ARCHIVE_FILE" | awk '{print $9 ": " $5}'

    # Calculate compression ratio (macOS compatible)
    ORIGINAL_SIZE=$(stat -f %z "$ITEMS_FILE" "$COLLECTIONS_FILE" 2>/dev/null | awk '{sum += $1} END {print sum}')
    if [ -z "$ORIGINAL_SIZE" ]; then
        # Linux fallback
        ORIGINAL_SIZE=$(stat -c %s "$ITEMS_FILE" "$COLLECTIONS_FILE" 2>/dev/null | awk '{sum += $1} END {print sum}')
    fi
    COMPRESSED_SIZE=$(stat -f %z "$ARCHIVE_FILE" 2>/dev/null || stat -c %s "$ARCHIVE_FILE" 2>/dev/null)
    if [ -n "$ORIGINAL_SIZE" ] && [ -n "$COMPRESSED_SIZE" ]; then
        RATIO=$(echo "scale=2; (1 - $COMPRESSED_SIZE / $ORIGINAL_SIZE) * 100" | bc)
    else
        RATIO="N/A"
    fi

    echo ""
    echo "Compression ratio: ${RATIO}% size reduction"
else
    echo "Error: Failed to create archive"
    exit 1
fi