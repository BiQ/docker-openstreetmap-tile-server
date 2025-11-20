#!/bin/bash

set -euo pipefail

# Prerender tiles for a given geographic bounding box
# Usage: prerender-tiles.sh <min_lat> <min_lon> <max_lat> <max_lon> <min_zoom> <max_zoom>

if [ $# -ne 6 ]; then
    echo "Usage: $0 <min_lat> <min_lon> <max_lat> <max_lon> <min_zoom> <max_zoom>"
    echo "Example: $0 54.4 8.0 57.8 15.2 0 15"
    exit 1
fi

MIN_LAT=$1
MIN_LON=$2
MAX_LAT=$3
MAX_LON=$4
MIN_ZOOM=$5
MAX_ZOOM=$6

# Configuration for error handling and progress reporting
MAX_CONSECUTIVE_FAILURES=${MAX_CONSECUTIVE_FAILURES:-10}
PROGRESS_PERCENT_STEP=${PROGRESS_PERCENT_STEP:-10}

echo "Starting prerendering for bounds: ($MIN_LAT,$MIN_LON) to ($MAX_LAT,$MAX_LON)"
echo "Zoom levels: $MIN_ZOOM to $MAX_ZOOM"

# Function to convert lat/lon to tile coordinates
deg2num() {
    local lat_deg=$1
    local lon_deg=$2
    local zoom=$3

    # Use a Python one-liner for accurate calculation
    local tiles=$(python3 -c "
import math
lat_rad = math.radians($lat_deg)
n = 2.0 ** $zoom
xtile = int((($lon_deg + 180.0) / 360.0) * n)
ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
print(f'{xtile} {ytile}')
")

    echo $tiles
}

# Setup style and generate mapnik.xml if needed
echo "Setting up style configuration..."
# Auto-populate /data/style/ if empty and osm-bright style is requested
if [ "${STYLE_TYPE:-}" == "osm-bright" ] && [ ! "$(ls -A /data/style/)" ]; then
    echo "INFO: /data/style/ is empty. Populating from /home/renderer/src/osm-bright-backup..."
    cp -r /home/renderer/src/osm-bright-backup/* /data/style/
fi

if [ ! "$(ls -A /data/style/)" ]; then
    echo "ERROR: No style found in /data/style/"
    exit 1
fi

# Set up the style based on STYLE_TYPE
if [ "${STYLE_TYPE:-}" == "osm-bright" ]; then
    echo "INFO: Configuring for osm-bright style"
    cd /data/style

    # Generate mapnik.xml if it doesn't exist
    if [ ! -f mapnik.xml ]; then
        echo "INFO: Generating mapnik.xml from project.mml"
        if [ -f project.mml ]; then
            carto project.mml > mapnik.xml
        else
            echo "ERROR: project.mml not found in /data/style/"
            exit 1
        fi
    fi

    # Update renderd config to use the correct mapnik.xml path
    MAPNIK_XML_PATH="/data/style/mapnik.xml"
else
    echo "INFO: Configuring for openstreetmap-carto style"
    MAPNIK_XML_PATH="/home/renderer/src/openstreetmap-carto/mapnik.xml"
fi

# Verify mapnik.xml exists
if [ ! -f "$MAPNIK_XML_PATH" ]; then
    echo "ERROR: Mapnik XML file not found at $MAPNIK_XML_PATH"
    echo "Available files in /data/style/:"
    ls -la /data/style/ || echo "No files found"
    exit 1
fi

echo "INFO: Using mapnik.xml at: $MAPNIK_XML_PATH"

# Create a custom renderd config for prerendering
cat > /etc/renderd.conf << EOF
[renderd]
num_threads=4
tile_dir=/var/cache/renderd/tiles
stats_file=/run/renderd/renderd.stats

[mapnik]
plugins_dir=/usr/lib/mapnik/3.1/input
font_dir=/usr/share/fonts
font_dir_recurse=1

[default]
URI=/tile/
TILEDIR=/var/cache/renderd/tiles
XML=$MAPNIK_XML_PATH
HOST=localhost
TILESIZE=256
MAXZOOM=20
EOF

echo "INFO: Updated renderd configuration"

# Start PostgreSQL and renderd
echo "Starting services..."
service postgresql start

# Start renderd in background
sudo -u renderer renderd -f -c /etc/renderd.conf &
RENDERD_PID=$!

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Check if renderd is running
if ! kill -0 $RENDERD_PID 2>/dev/null; then
    echo "ERROR: renderd failed to start"
    exit 1
fi

# Test if Apache is needed (start it if curl fails)
if ! curl -s "http://localhost/tile/0/0/0.png" > /dev/null 2>&1; then
    echo "INFO: Starting Apache web server..."
    service apache2 start
    sleep 5
fi

echo "Services started successfully"

# Calculate total tiles for progress tracking
TOTAL_TILES=0
for zoom in $(seq $MIN_ZOOM $MAX_ZOOM); do
    tiles_min=$(deg2num $MIN_LAT $MIN_LON $zoom)
    tiles_max=$(deg2num $MAX_LAT $MAX_LON $zoom)

    min_x=$(echo $tiles_min | cut -d' ' -f1)
    min_y=$(echo $tiles_max | cut -d' ' -f2)  # Note: max lat gives min y
    max_x=$(echo $tiles_max | cut -d' ' -f1)
    max_y=$(echo $tiles_min | cut -d' ' -f2)  # Note: min lat gives max y

    tiles_this_zoom=$(( (max_x - min_x + 1) * (max_y - min_y + 1) ))
    TOTAL_TILES=$((TOTAL_TILES + tiles_this_zoom))

    echo "Zoom $zoom: tiles ($min_x,$min_y) to ($max_x,$max_y) = $tiles_this_zoom tiles"
done

echo "Total tiles to render: $TOTAL_TILES"

# Prerender tiles
RENDERED_TILES=0
CONSECUTIVE_FAILURES=0
NEXT_PROGRESS_PERCENT=$PROGRESS_PERCENT_STEP
START_TIME=$(date +%s)

for zoom in $(seq $MIN_ZOOM $MAX_ZOOM); do
    echo "Rendering zoom level $zoom..."

    # Calculate tile bounds for this zoom level
    tiles_min=$(deg2num $MIN_LAT $MIN_LON $zoom)
    tiles_max=$(deg2num $MAX_LAT $MAX_LON $zoom)

    min_x=$(echo $tiles_min | cut -d' ' -f1)
    min_y=$(echo $tiles_max | cut -d' ' -f2)  # Note: max lat gives min y
    max_x=$(echo $tiles_max | cut -d' ' -f1)
    max_y=$(echo $tiles_min | cut -d' ' -f2)  # Note: min lat gives max y

    echo "Zoom $zoom bounds: x=$min_x-$max_x, y=$min_y-$max_y"

    # Render tiles for this zoom level
    for x in $(seq $min_x $max_x); do
        for y in $(seq $min_y $max_y); do
            # Request tile to trigger rendering
            if curl -s "http://localhost/tile/$zoom/$x/$y.png" > /dev/null; then
                echo "Successfully rendered tile $zoom/$x/$y"
                CONSECUTIVE_FAILURES=0
            else
                echo "Failed to render tile $zoom/$x/$y"
                CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
                if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
                    echo "Error: Exceeded maximum consecutive tile rendering failures ($MAX_CONSECUTIVE_FAILURES). Halting prerendering."
                    exit 2
                fi
            fi

            RENDERED_TILES=$((RENDERED_TILES + 1))

            # Progress reporting based on percentage intervals
            PERCENT=$((RENDERED_TILES * 100 / TOTAL_TILES))
            if [ $PERCENT -ge $NEXT_PROGRESS_PERCENT ] || [ $RENDERED_TILES -eq $TOTAL_TILES ]; then
                CURRENT_TIME=$(date +%s)
                ELAPSED=$((CURRENT_TIME - START_TIME))
                
                if [ "$ELAPSED" -le 0 ]; then
                    RATE=0
                else
                    RATE=$((RENDERED_TILES / ELAPSED))
                fi
                
                if [ "$RATE" -gt 0 ]; then
                    ETA=$(( (TOTAL_TILES - RENDERED_TILES) / RATE ))
                else
                    ETA="N/A"
                fi

                echo "Progress: $RENDERED_TILES/$TOTAL_TILES ($PERCENT%) - Rate: ${RATE} tiles/sec - ETA: ${ETA}s"
                NEXT_PROGRESS_PERCENT=$((NEXT_PROGRESS_PERCENT + PROGRESS_PERCENT_STEP))
            fi
        done
    done

    echo "Completed zoom level $zoom"
done

# Stop services
kill $RENDERD_PID 2>/dev/null || true
service apache2 stop 2>/dev/null || true
service postgresql stop

TOTAL_TIME=$(($(date +%s) - START_TIME))
if [ "$TOTAL_TIME" -eq 0 ]; then
    FINAL_RATE="N/A"
else
    FINAL_RATE=$((RENDERED_TILES / TOTAL_TIME))
fi

echo "Prerendering completed!"
echo "Total tiles rendered: $RENDERED_TILES"
echo "Total time: ${TOTAL_TIME}s"
echo "Average rate: ${FINAL_RATE} tiles/sec"
