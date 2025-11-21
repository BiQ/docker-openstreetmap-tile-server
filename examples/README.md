# Example Scripts for OSM Tile Server Setup

This directory contains example scripts demonstrating how to set up and use the OpenStreetMap tile server with different configurations.

## Available Examples

### 1. Europe with OSM Bright Style

**Script:** `europe-osm-bright-setup.sh`

Complete production setup for Europe using OSM Bright style with prerendering.

**Features:**
- Downloads and imports full Europe OSM data (~25GB)
- Prerenders tiles for zoom levels 0-14
- Optimized for production use

**Requirements:**
- 200GB+ disk space
- 16GB+ RAM recommended
- 6-12 hours for import
- 15-20 hours for prerendering

**Usage:**
```bash
./europe-osm-bright-setup.sh
```

**Result:**
- Running tile server at http://localhost:8080
- Prerendered ~8.9 million tiles
- Ready for production traffic

---

### 2. Luxembourg Test Setup

**Script:** `luxembourg-test.sh`

Quick test setup using Luxembourg data - ideal for testing and development.

**Features:**
- Downloads Luxembourg OSM data (~50MB)
- Prerenders tiles for zoom levels 0-12
- Fast setup for testing

**Requirements:**
- 5GB disk space
- 4GB RAM
- ~30 minutes total time

**Usage:**
```bash
./luxembourg-test.sh
```

**Result:**
- Running tile server at http://localhost:8080
- Prerendered tiles for Luxembourg
- Good for testing the prerender functionality

---

## Customization

You can customize these scripts by editing the configuration variables at the top:

```bash
VOLUME_NAME="your-volume-name"
CONTAINER_IMAGE="biqaps/openstreetmap:3.0"
STYLE_TYPE="osm-bright"              # or "openstreetmap-carto"
REGION="europe"                      # or custom bbox
MIN_ZOOM="0"
MAX_ZOOM="14"
THREADS="8"                          # adjust based on CPU cores
```

## Custom Regions

To set up a custom region:

1. Find your region on [Geofabrik](https://download.geofabrik.de/)
2. Copy one of the example scripts
3. Update the `DOWNLOAD_PBF` and `DOWNLOAD_POLY` URLs
4. Update the `REGION` variable or use `PRERENDER_BBOX`
5. Adjust zoom levels as needed

Example for Germany:
```bash
DOWNLOAD_PBF=https://download.geofabrik.de/europe/germany-latest.osm.pbf
DOWNLOAD_POLY=https://download.geofabrik.de/europe/germany.poly
REGION="germany"
MIN_ZOOM="0"
MAX_ZOOM="14"
```

## Prerendering Tips

### Zoom Level Selection

- **Zoom 0-8**: Overview maps, fast prerender (~2000 tiles for Europe)
- **Zoom 0-12**: City-level detail (~500K tiles for Europe, ~1-2 hours)
- **Zoom 0-14**: Standard production (~8.9M tiles for Europe, ~15-20 hours)
- **Zoom 0-16**: High detail (very large, only for specific areas)

### Performance Optimization

1. **Threads**: Set based on CPU cores (e.g., 8-16 for production servers)
2. **Memory**: Use `--shm-size=512m` or higher for large datasets
3. **Disk**: SSD strongly recommended for better I/O performance
4. **Incremental**: Consider prerendering in stages (0-8, then 9-12, then 13-14)

### Custom Bounding Box

Instead of predefined regions, you can use a custom bounding box:

```bash
# In the prerender step, replace PRERENDER_REGION with:
-e PRERENDER_BBOX="min_lat,min_lon,max_lat,max_lon"

# Example for Benelux region:
-e PRERENDER_BBOX="49.5,2.5,53.5,7.5"
```

## Monitoring Progress

When prerendering, the script will output progress for each zoom level:

```
Prerendering tiles for zoom levels 0-14
Bounding box: lat(35.0, 71.0), lon(-10.0, 40.0)
Using 8 threads

Zoom 0: 1 tiles (x: 0-0, y: 0-0)
  Zoom 0 complete: 1 successful, 0 failed

Zoom 1: 2 tiles (x: 0-1, y: 0-0)
  Zoom 1 complete: 2 successful, 0 failed

...
```

## Troubleshooting

### Import Fails
- Check disk space: `df -h`
- Increase `--shm-size` if you see shared memory errors
- Verify PBF file downloaded correctly

### Prerender Fails
- Ensure import completed successfully
- Check that tile server is running
- Verify network connectivity between containers

### Out of Memory
- Reduce `THREADS` value
- Increase `--shm-size`
- Add swap space to your system

## Additional Resources

- [Geofabrik Downloads](https://download.geofabrik.de/) - OSM data extracts
- [OSM Bright Style](https://github.com/mapbox/osm-bright) - Style documentation
- [Switch2OSM](https://switch2osm.org/) - Tile server guides
