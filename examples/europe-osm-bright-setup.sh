#!/bin/bash
#
# Complete example for setting up Europe OSM Bright tile server with prerendering
#
# This script demonstrates the full workflow:
# 1. Import Europe OSM data
# 2. Prerender tiles for Europe at zoom levels 0-14
# 3. Run the tile server
#
# Usage:
#   ./europe-osm-bright-setup.sh
#
# Requirements:
# - Docker installed and running
# - Sufficient disk space (200GB+ recommended)
# - Good internet connection for downloading Europe data (~25GB)
# - Time: Import ~6-12 hours, Prerender ~15-20 hours on modern hardware

set -e

# Configuration
VOLUME_NAME="europe-osm-data"
CONTAINER_IMAGE="biqaps/openstreetmap:3.0"
STYLE_TYPE="osm-bright"
REGION="europe"
MIN_ZOOM="0"
MAX_ZOOM="14"
THREADS="8"

echo "=========================================="
echo "Europe OSM Bright Tile Server Setup"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Volume: $VOLUME_NAME"
echo "  Image: $CONTAINER_IMAGE"
echo "  Style: $STYLE_TYPE"
echo "  Region: $REGION"
echo "  Zoom levels: $MIN_ZOOM - $MAX_ZOOM"
echo "  Threads: $THREADS"
echo ""
echo "Estimated requirements:"
echo "  Download: ~25GB (Europe PBF)"
echo "  Import time: 6-12 hours"
echo "  Prerender time: 15-20 hours"
echo "  Storage: 200GB+"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Step 1: Create volume
echo ""
echo "Step 1: Creating Docker volume..."
docker volume create "$VOLUME_NAME"

# Step 2: Import Europe data
echo ""
echo "Step 2: Importing Europe OSM data..."
echo "This will take 6-12 hours depending on your hardware"
echo ""
docker run \
    --rm \
    --shm-size=512m \
    -v "$VOLUME_NAME:/data/database/" \
    -e STYLE_TYPE="$STYLE_TYPE" \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe.poly \
    -e THREADS="$THREADS" \
    "$CONTAINER_IMAGE" \
    import

# Step 3: Prerender tiles
echo ""
echo "Step 3: Prerendering tiles for Europe (zoom $MIN_ZOOM-$MAX_ZOOM)..."
echo "This will take approximately 15-20 hours"
echo "Progress will be displayed below..."
echo ""
docker run \
    --rm \
    --shm-size=512m \
    -v "$VOLUME_NAME:/data/database/" \
    -e STYLE_TYPE="$STYLE_TYPE" \
    -e PRERENDER_REGION="$REGION" \
    -e PRERENDER_MIN_ZOOM="$MIN_ZOOM" \
    -e PRERENDER_MAX_ZOOM="$MAX_ZOOM" \
    -e PRERENDER_THREADS="$THREADS" \
    "$CONTAINER_IMAGE" \
    prerender

# Step 4: Start tile server
echo ""
echo "Step 4: Starting tile server..."
docker run \
    -p 8080:80 \
    --shm-size=512m \
    -v "$VOLUME_NAME:/data/database/" \
    -e STYLE_TYPE="$STYLE_TYPE" \
    -d \
    --name europe-tile-server \
    "$CONTAINER_IMAGE" \
    run

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Tile server is now running at:"
echo "  Map interface: http://localhost:8080"
echo "  Tile API: http://localhost:8080/tile/{z}/{x}/{y}.png"
echo ""
echo "Example tiles:"
echo "  http://localhost:8080/tile/0/0/0.png"
echo "  http://localhost:8080/tile/5/16/10.png (Europe overview)"
echo "  http://localhost:8080/tile/10/524/340.png (Central Europe)"
echo ""
echo "To stop the server:"
echo "  docker stop europe-tile-server"
echo ""
echo "To restart the server:"
echo "  docker start europe-tile-server"
echo ""
echo "To remove everything:"
echo "  docker rm -f europe-tile-server"
echo "  docker volume rm $VOLUME_NAME"
echo ""
