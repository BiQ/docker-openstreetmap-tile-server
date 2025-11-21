#!/bin/bash
#
# Quick test example for Luxembourg with OSM Bright and prerendering
#
# This is a smaller example suitable for testing the prerender functionality
# Uses Luxembourg data which is much smaller than full Europe
#
# Usage:
#   ./luxembourg-test.sh
#
# Requirements:
# - Docker installed and running
# - ~5GB disk space
# - ~30 minutes for import and prerender

set -e

# Configuration
VOLUME_NAME="luxembourg-test-data"
CONTAINER_IMAGE="biqaps/openstreetmap:3.0"
STYLE_TYPE="osm-bright"
REGION="luxembourg"
MIN_ZOOM="0"
MAX_ZOOM="12"
THREADS="4"

echo "=========================================="
echo "Luxembourg Test - OSM Bright with Prerender"
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
echo "This is a test setup using Luxembourg data."
echo "Estimated time: ~30 minutes total"
echo ""

# Step 1: Create volume
echo "Step 1: Creating Docker volume..."
docker volume create "$VOLUME_NAME"

# Step 2: Import Luxembourg data
echo ""
echo "Step 2: Importing Luxembourg OSM data..."
docker run \
    --rm \
    --shm-size=192m \
    -v "$VOLUME_NAME:/data/database/" \
    -e STYLE_TYPE="$STYLE_TYPE" \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -e THREADS="$THREADS" \
    "$CONTAINER_IMAGE" \
    import

# Step 3: Prerender tiles
echo ""
echo "Step 3: Prerendering tiles for Luxembourg (zoom $MIN_ZOOM-$MAX_ZOOM)..."
docker run \
    --rm \
    --shm-size=192m \
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
    --shm-size=192m \
    -v "$VOLUME_NAME:/data/database/" \
    -e STYLE_TYPE="$STYLE_TYPE" \
    -d \
    --name luxembourg-tile-server \
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
echo "Example tiles for Luxembourg:"
echo "  http://localhost:8080/tile/0/0/0.png (World)"
echo "  http://localhost:8080/tile/8/130/88.png (Luxembourg area)"
echo "  http://localhost:8080/tile/12/2084/1409.png (Luxembourg city)"
echo ""
echo "To stop the server:"
echo "  docker stop luxembourg-tile-server"
echo ""
echo "To clean up:"
echo "  docker rm -f luxembourg-tile-server"
echo "  docker volume rm $VOLUME_NAME"
echo ""
