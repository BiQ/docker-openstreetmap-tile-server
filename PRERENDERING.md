# Prerendering Guide for Europe OSM Bright Tiles

This guide walks through the complete process of setting up a production-ready OpenStreetMap tile server for Europe using the OSM Bright style with prerendered tiles.

## Quick Start

For a complete automated setup, use the example script:

```bash
./examples/europe-osm-bright-setup.sh
```

This will:
1. Create a Docker volume
2. Download and import Europe OSM data
3. Prerender tiles for zoom levels 0-14
4. Start the tile server

## Manual Step-by-Step Guide

### Step 1: Create Data Volume

```bash
docker volume create europe-osm-data
```

### Step 2: Import Europe Data

Download and import the Europe OSM data (this takes 6-12 hours):

```bash
docker run \
    --rm \
    --shm-size=512m \
    -v europe-osm-data:/data/database/ \
    -e STYLE_TYPE=osm-bright \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe.poly \
    -e THREADS=8 \
    biqaps/openstreetmap:3.0 \
    import
```

**What happens:**
- Downloads ~25GB Europe PBF file
- Imports into PostgreSQL/PostGIS database
- Sets up OSM Bright style
- Configures external data sources

### Step 3: Prerender Tiles

Prerender tiles for Europe at zoom levels 0-14 (this takes 15-20 hours):

```bash
docker run \
    --rm \
    --shm-size=512m \
    -v europe-osm-data:/data/database/ \
    -e STYLE_TYPE=osm-bright \
    -e PRERENDER_REGION=europe \
    -e PRERENDER_MIN_ZOOM=0 \
    -e PRERENDER_MAX_ZOOM=14 \
    -e PRERENDER_THREADS=8 \
    biqaps/openstreetmap:3.0 \
    prerender
```

**Progress output:**
```
Prerendering tiles for zoom levels 0-14
Bounding box: lat(35.0, 71.0), lon(-10.0, 40.0)
Using 8 threads

Zoom 0: 1 tiles (x: 0-0, y: 0-0)
  Zoom 0 complete: 1 successful, 0 failed

Zoom 1: 2 tiles (x: 0-1, y: 0-0)
  Zoom 1 complete: 2 successful, 0 failed

...

Zoom 14: 6739920 tiles (x: 8192-24575, y: 5461-10922)
  Progress: 6739920/6739920 tiles (100.0%)
  Zoom 14 complete: 6739920 successful, 0 failed

============================================================
Prerendering complete!
Total tiles: 8983261
Successful: 8983261
Failed: 0
```

### Step 4: Run Tile Server

Start the tile server with prerendered tiles:

```bash
docker run \
    -p 8080:80 \
    --shm-size=512m \
    -v europe-osm-data:/data/database/ \
    -e STYLE_TYPE=osm-bright \
    -d \
    --name europe-tile-server \
    biqaps/openstreetmap:3.0 \
    run
```

## Accessing Your Tiles

### Web Interface

Open your browser to:
```
http://localhost:8080
```

### Tile API

Access individual tiles at:
```
http://localhost:8080/tile/{z}/{x}/{y}.png
```

**Example tiles:**
- `http://localhost:8080/tile/0/0/0.png` - World overview
- `http://localhost:8080/tile/5/16/10.png` - Europe overview
- `http://localhost:8080/tile/10/524/340.png` - Central Europe
- `http://localhost:8080/tile/14/8386/5461.png` - Detailed city view

## Customization Options

### Zoom Level Selection

Adjust zoom levels based on your needs:

```bash
# Light traffic / overview maps (fast, ~2000 tiles)
-e PRERENDER_MIN_ZOOM=0 \
-e PRERENDER_MAX_ZOOM=8

# Medium traffic / city-level (~500K tiles, ~2 hours)
-e PRERENDER_MIN_ZOOM=0 \
-e PRERENDER_MAX_ZOOM=12

# Production deployment (8.9M tiles, ~20 hours)
-e PRERENDER_MIN_ZOOM=0 \
-e PRERENDER_MAX_ZOOM=14

# High detail (very large, use only for specific areas)
-e PRERENDER_MIN_ZOOM=0 \
-e PRERENDER_MAX_ZOOM=16
```

### Custom Region

Use a custom bounding box instead of predefined Europe:

```bash
# Benelux region example
-e PRERENDER_BBOX="49.5,2.5,53.5,7.5" \
-e PRERENDER_MIN_ZOOM=0 \
-e PRERENDER_MAX_ZOOM=14
```

### Performance Tuning

**Threads:**
```bash
# Adjust based on CPU cores (recommended: number of cores)
-e PRERENDER_THREADS=16
```

**Memory:**
```bash
# Increase shared memory for better performance
--shm-size=1g
```

**Import Threads:**
```bash
# Parallel import processes
-e THREADS=16
```

## Resource Requirements

### Minimum Requirements
- CPU: 4 cores
- RAM: 8GB
- Disk: 100GB free space
- Time: ~24 hours total

### Recommended for Production
- CPU: 16+ cores
- RAM: 32GB+
- Disk: 250GB+ SSD
- Time: ~18 hours total

### Disk Space Breakdown
- Europe PBF: ~25GB
- PostgreSQL database: ~40-80GB
- Prerendered tiles (zoom 0-14): ~50-150GB
- Working space: ~20GB
- **Total: ~200GB**

## Monitoring and Maintenance

### Check Server Status

```bash
docker logs europe-tile-server
```

### View Container Stats

```bash
docker stats europe-tile-server
```

### Restart Server

```bash
docker restart europe-tile-server
```

### Stop Server

```bash
docker stop europe-tile-server
```

### Backup Data

```bash
# Export volume to tarball
docker run --rm -v europe-osm-data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/europe-osm-data.tar.gz /data
```

### Restore Data

```bash
# Create new volume
docker volume create europe-osm-data-restored

# Restore from tarball
docker run --rm -v europe-osm-data-restored:/data -v $(pwd):/backup \
  ubuntu tar xzf /backup/europe-osm-data.tar.gz -C /
```

## Troubleshooting

### Import Fails

**Problem:** Import exits with error

**Solutions:**
- Check disk space: `df -h`
- Increase shared memory: `--shm-size=1g`
- Verify PBF download: Check file size (~25GB for Europe)
- Check logs: `docker logs <container>`

### Prerender Appears Stuck

**Problem:** Progress not updating

**Solutions:**
- Progress updates every 5 seconds or 100 tiles
- For large zoom levels (13-14), rendering takes significant time per tile
- Check server logs: `docker logs europe-tile-server`
- Verify server is running: `docker ps`

### Out of Memory

**Problem:** Container killed or OOM errors

**Solutions:**
- Increase Docker memory limit
- Add system swap space
- Reduce parallel threads: `-e PRERENDER_THREADS=4`
- Increase shared memory: `--shm-size=1g`

### Tiles Not Rendering

**Problem:** HTTP 500 or blank tiles

**Solutions:**
- Check PostgreSQL is running: `docker exec europe-tile-server pg_isready`
- Verify import completed: Check for `/data/database/planet-import-complete`
- Check renderd logs: `docker logs europe-tile-server | grep renderd`
- Restart server: `docker restart europe-tile-server`

## Advanced Usage

### Incremental Prerendering

Prerender in stages to save time:

```bash
# Stage 1: Low zoom (fast)
docker run ... -e PRERENDER_MAX_ZOOM=8 ... prerender

# Stage 2: Medium zoom
docker run ... -e PRERENDER_MIN_ZOOM=9 -e PRERENDER_MAX_ZOOM=12 ... prerender

# Stage 3: High zoom (slow)
docker run ... -e PRERENDER_MIN_ZOOM=13 -e PRERENDER_MAX_ZOOM=14 ... prerender
```

### Multiple Regions

Run multiple tile servers for different regions:

```bash
# Europe server
docker run -p 8080:80 --name europe-tiles ...

# North America server  
docker run -p 8081:80 --name na-tiles ...
```

### Automated Updates

Enable automatic OSM updates:

```bash
docker run \
    -p 8080:80 \
    -e UPDATES=enabled \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/ \
    -v europe-osm-data:/data/database/ \
    -d europe-tile-server \
    run
```

## Performance Benchmarks

Based on testing with various hardware configurations:

### Import Times (Europe)
- 4 cores, 8GB RAM, HDD: ~12 hours
- 8 cores, 16GB RAM, SSD: ~6 hours
- 16 cores, 32GB RAM, NVMe: ~4 hours

### Prerender Times (Europe, zoom 0-14)
- 4 threads: ~24-30 hours
- 8 threads: ~15-20 hours
- 16 threads: ~10-15 hours

### Tile Counts by Zoom Level
| Zoom | Tiles | Time (8 threads) |
|------|-------|------------------|
| 0-8  | ~2,000 | ~1 minute |
| 0-10 | ~27,000 | ~15 minutes |
| 0-12 | ~423,000 | ~2 hours |
| 0-14 | ~8.9M | ~18 hours |

## Additional Resources

- [Geofabrik Downloads](https://download.geofabrik.de/) - OSM data extracts
- [OSM Bright Documentation](https://github.com/mapbox/osm-bright)
- [Switch2OSM Guide](https://switch2osm.org/)
- [Tile Server Benchmarks](https://wiki.openstreetmap.org/wiki/Osm2pgsql/benchmarks)
