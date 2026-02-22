#!/bin/bash
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$BASE/data"
ARCHIVE="$DEST/dataset.zip"
URL="https://maven-datasets.s3.us-east-1.amazonaws.com/Maven+Fuzzy+Factory/Maven+Fuzzy+Factory.zip"

REQUIRED=(products.csv website_sessions.csv website_pageviews.csv orders.csv order_items.csv order_item_refunds.csv)

mkdir -p "$DEST"

for f in "${REQUIRED[@]}"; do
    if [[ ! -f "$DEST/$f" ]]; then
        echo "Downloading Maven Fuzzy Factory dataset..."
        wget -q -O "$ARCHIVE" "$URL"
        echo "Extracting..."
        unzip -j -o "$ARCHIVE" "*.csv" -d "$DEST" -x "__MACOSX/*" > /dev/null
        rm "$ARCHIVE"
        echo "Done."
        exit 0
    fi
done

echo "Dataset already present — skipping download."
