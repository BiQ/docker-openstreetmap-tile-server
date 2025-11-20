# openstreetmap-tile-server

[![Build Status](https://travis-ci.org/Overv/openstreetmap-tile-server.svg?branch=master)](https://travis-ci.org/Overv/openstreetmap-tile-server) [![](https://images.microbadger.com/badges/image/overv/openstreetmap-tile-server.svg)](https://microbadger.com/images/overv/openstreetmap-tile-server "openstreetmap-tile-server")
[![Docker Image Version (latest semver)](https://img.shields.io/docker/v/overv/openstreetmap-tile-server?label=docker%20image)](https://hub.docker.com/r/overv/openstreetmap-tile-server/tags)

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [latest Ubuntu 18.04 LTS guide](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/) from [switch2osm.org](https://switch2osm.org/) and supports both the default OpenStreetMap style and the osm-bright style.

## New Features: OSM-Bright Style & GeoDanmark Support

This image now supports building OpenStreetMap tile servers with:
- **OSM-Bright style**: A clean, minimalist map style developed by Mapbox
- **GeoDanmark integration**: Support for incorporating GeoDanmark shapefiles for enhanced Denmark mapping
- **Denmark-optimized setup**: Automatic Denmark OSM data download when using osm-bright style

### Using OSM-Bright Style

To use the osm-bright style instead of the default openstreetmap-carto:

```bash
# Build with Denmark data and osm-bright style
docker run \
    -e STYLE_TYPE=osm-bright \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/denmark-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/denmark.poly \
    -v osm-data:/data/database/ \
    biqaps/openstreetmap:3.0 \
    import

# Run the tile server
docker run \
    -p 8080:80 \
    -e STYLE_TYPE=osm-bright \
    -v osm-data:/data/database/ \
    -d biqaps/openstreetmap:3.0 \
    run
```

### GeoDanmark Integration

To enable GeoDanmark shapefile integration (for enhanced Denmark mapping):

```bash
# Note: GeoDanmark files are large (~4GB) and require manual download
# from https://download.kortforsyningen.dk/content/geodanmark
docker run \
    -e STYLE_TYPE=osm-bright \
    -e DOWNLOAD_GEODANMARK=enabled \
    -v osm-data:/data/database/ \
    biqaps/openstreetmap:3.0 \
    import
```

### Prerendering Tiles

The tile server now supports batch prerendering of tiles for faster initial load times. This is especially useful for production deployments where you want to cache tiles before serving them to users.

#### Prerender Europe with OSM-Bright Style

Here's a complete example for setting up and prerendering tiles for Europe using OSM-Bright style:

```bash
# Create a data volume
docker volume create europe-osm-data

# Import Europe OSM data with osm-bright style
docker run \
    -e STYLE_TYPE=osm-bright \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe.poly \
    -v europe-osm-data:/data/database/ \
    --shm-size=512m \
    biqaps/openstreetmap:3.0 \
    import

# Prerender tiles for Europe at zoom levels 0-14
docker run \
    -e STYLE_TYPE=osm-bright \
    -e PRERENDER_REGION=europe \
    -e PRERENDER_MIN_ZOOM=0 \
    -e PRERENDER_MAX_ZOOM=14 \
    -e PRERENDER_THREADS=8 \
    -v europe-osm-data:/data/database/ \
    --shm-size=512m \
    biqaps/openstreetmap:3.0 \
    prerender

# Run the tile server with prerendered tiles
docker run \
    -p 8080:80 \
    -e STYLE_TYPE=osm-bright \
    -v europe-osm-data:/data/database/ \
    --shm-size=512m \
    -d biqaps/openstreetmap:3.0 \
    run
```

#### Prerendering Environment Variables

- `PRERENDER_REGION`: Predefined region to prerender. Options: `world`, `europe`, `denmark`, `luxembourg`, `germany`, `france`, `uk`, `spain`, `italy`
- `PRERENDER_BBOX`: Custom bounding box as `min_lat,min_lon,max_lat,max_lon` (alternative to PRERENDER_REGION)
- `PRERENDER_MIN_ZOOM`: Minimum zoom level to prerender (default: 0)
- `PRERENDER_MAX_ZOOM`: Maximum zoom level to prerender (default: 14)
- `PRERENDER_THREADS`: Number of parallel rendering threads (default: 4)

#### Zoom Level Recommendations

For production tile servers, the following zoom levels are recommended:

- **Light traffic / overview maps**: Zoom 0-8 (minimal tiles, fast prerender)
- **Medium traffic / city-level**: Zoom 0-12 (balanced coverage)
- **Production deployment**: Zoom 0-14 (standard recommendation, ~15-20 hours for Europe)
- **High detail areas**: Zoom 0-16 (large areas only, very time-consuming)

#### Custom Bounding Box Example

To prerender a custom region, use the `PRERENDER_BBOX` variable:

```bash
# Prerender custom bounding box (e.g., Benelux region)
docker run \
    -e STYLE_TYPE=osm-bright \
    -e PRERENDER_BBOX="49.5,2.5,53.5,7.5" \
    -e PRERENDER_MIN_ZOOM=0 \
    -e PRERENDER_MAX_ZOOM=14 \
    -v europe-osm-data:/data/database/ \
    biqaps/openstreetmap:3.0 \
    prerender
```

#### Performance Considerations

- **Memory**: Use `--shm-size=512m` or higher for large imports and prerendering
- **Disk Space**: Europe at zoom 0-14 requires significant storage (50-200GB depending on style)
- **Time**: Prerendering Europe at zoom 0-14 can take 15-20 hours on a modern server
- **Threads**: Increase `PRERENDER_THREADS` based on your CPU cores (e.g., 8-16 for production servers)

#### Ready-to-Use Example Scripts

Complete example scripts for common scenarios are available in the [`examples/`](examples/) directory:
- **Europe setup**: Full production setup with prerendering ([`europe-osm-bright-setup.sh`](examples/europe-osm-bright-setup.sh))
- **Luxembourg test**: Quick test setup for development ([`luxembourg-test.sh`](examples/luxembourg-test.sh))

See the [examples README](examples/README.md) for detailed usage instructions and customization options.

### Complete Example: Denmark with OSM-Bright and GeoDanmark

Here's a complete example for setting up a Denmark tile server with osm-bright style and GeoDanmark integration:

```bash
# Create a data volume
docker volume create denmark-osm-data

# Import Denmark OSM data with osm-bright style
docker run \
    -e STYLE_TYPE=osm-bright \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/denmark-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/denmark.poly \
    -e DOWNLOAD_GEODANMARK=enabled \
    -v denmark-osm-data:/data/database/ \
    biqaps/openstreetmap:3.0 \
    import

# Run the tile server
docker run \
    -p 8080:80 \
    -e STYLE_TYPE=osm-bright \
    -v denmark-osm-data:/data/database/ \
    -d biqaps/openstreetmap:3.0 \
    run
```

### Environment Variables

The following environment variables control the tile server behavior:

**General Variables:**
- `STYLE_TYPE`: Set to `osm-bright` for OSM-Bright style, or `openstreetmap-carto` (default) for the standard style
- `DOWNLOAD_GEODANMARK`: Set to `enabled` to download GeoDanmark shapefiles (requires large download)
- `DOWNLOAD_PBF`: URL to download OSM PBF data file
- `DOWNLOAD_POLY`: URL to download polygon boundary file
- `THREADS`: Number of threads for importing and rendering (default: 4)
- `UPDATES`: Set to `enabled` for automatic updates
- `NAME_LUA`, `NAME_STYLE`, `NAME_MML`, `NAME_SQL`: Override default style file names

**Prerendering Variables:**
- `PRERENDER_REGION`: Predefined region to prerender (world, europe, denmark, luxembourg, etc.)
- `PRERENDER_BBOX`: Custom bounding box as `min_lat,min_lon,max_lat,max_lon`
- `PRERENDER_MIN_ZOOM`: Minimum zoom level to prerender (default: 0)
- `PRERENDER_MAX_ZOOM`: Maximum zoom level to prerender (default: 14)
- `PRERENDER_THREADS`: Number of parallel rendering threads (default: 4)


### Production Considerations

For production use with GeoDanmark data:

1. **Manual GeoDanmark Download**: The GeoDanmark shapefiles are ~4GB and require registration at [Kortforsyningen](https://download.kortforsyningen.dk/content/geodanmark)
2. **External Data**: For production use, download the actual land polygon files:
   - `https://osmdata.openstreetmap.de/download/simplified-land-polygons-complete-3857.zip`
   - `https://osmdata.openstreetmap.de/download/land-polygons-split-3857.zip`
3. **Performance**: Use appropriate hardware and consider `FLAT_NODES=enabled` for large imports

### Testing the Setup

After starting the tile server, you can test it by accessing:

- **Map Interface**: `http://localhost:8080` - Interactive map interface
- **Tile API**: `http://localhost:8080/tile/{z}/{x}/{y}.png` - Direct tile access
- **Example Tile**: `http://localhost:8080/tile/10/512/512.png` - Sample tile

### Available Images

- **Standard Image**: `overv/openstreetmap-tile-server` - Original image with openstreetmap-carto style
- **OSM-Bright Image**: `biqaps/openstreetmap:3.0` - Enhanced image with osm-bright and GeoDanmark support

### Build from Source

To build the enhanced image locally:

```bash
git clone https://github.com/BiQ/docker-openstreetmap-tile-server.git
cd docker-openstreetmap-tile-server
make osm-bright-build
```

## Setting up the server

First create a Docker volume to hold the PostgreSQL database that will contain the OpenStreetMap data:

    docker volume create osm-data

Next, download an `.osm.pbf` extract from geofabrik.de for the region that you're interested in. You can then start importing it into PostgreSQL by running a container and mounting the file as `/data/region.osm.pbf`. For example:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v osm-data:/data/database/ \
    overv/openstreetmap-tile-server \
    import
```

If the container exits without errors, then your data has been successfully imported and you are now ready to run the tile server.

Note that the import process requires an internet connection. The run process does not require an internet connection. If you want to run the openstreetmap-tile server on a computer that is isolated, you must first import on an internet connected computer, export the `osm-data` volume as a tarfile, and then restore the data volume on the target computer system.

Also when running on an isolated system, the default `index.html` from the container will not work, as it requires access to the web for the leaflet packages.

### Automatic updates (optional)

If your import is an extract of the planet and has polygonal bounds associated with it, like those from [geofabrik.de](https://download.geofabrik.de/), then it is possible to set your server up for automatic updates. Make sure to reference both the OSM file and the polygon file during the `import` process to facilitate this, and also include the `UPDATES=enabled` variable:

```
docker run \
    -e UPDATES=enabled \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v /absolute/path/to/luxembourg.poly:/data/region.poly \
    -v osm-data:/data/database/ \
    overv/openstreetmap-tile-server \
    import
```

Refer to the section *Automatic updating and tile expiry* to actually enable the updates while running the tile server.

Please note: If you're not importing the whole planet, then the `.poly` file is necessary to limit automatic updates to the relevant region.
Therefore, when you only have a `.osm.pbf` file but not a `.poly` file, you should not enable automatic updates.

### Letting the container download the file

It is also possible to let the container download files for you rather than mounting them in advance by using the `DOWNLOAD_PBF` and `DOWNLOAD_POLY` parameters:

```
docker run \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -v osm-data:/data/database/ \
    overv/openstreetmap-tile-server \
    import
```

### Using an alternate style

By default the container will use openstreetmap-carto if it is not specified. However, you can modify the style at run-time. Be aware you need the style mounted at `run` AND `import` as the Lua script needs to be run:

```
docker run \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -e NAME_LUA=sample.lua \
    -e NAME_STYLE=test.style \
    -e NAME_MML=project.mml \
    -e NAME_SQL=test.sql \
    -v /home/user/openstreetmap-carto-modified:/data/style/ \
    -v osm-data:/data/database/ \
    overv/openstreetmap-tile-server \
    import
```

If you do not define the "NAME_*" variables, the script will default to those found in the openstreetmap-carto style.

Be sure to mount the volume during `run` with the same `-v /home/user/openstreetmap-carto-modified:/data/style/`

If you do not see the expected style upon `run` double check your paths as the style may not have been found at the directory specified. By default, `openstreetmap-carto` will be used if a style cannot be found

**Only openstreetmap-carto and styles like it, eg, ones with one lua script, one style, one mml, one SQL can be used**

## Running the server

Run the server like this:

```
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    -d overv/openstreetmap-tile-server \
    run
```

Your tiles will now be available at `http://localhost:8080/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will then be available on `http://localhost:8080`. Note that it will initially take quite a bit of time to render the larger tiles for the first time.

### Using Docker Compose

The `docker-compose.yml` file included with this repository shows how the aforementioned command can be used with Docker Compose to run your server.

### Preserving rendered tiles

Tiles that have already been rendered will be stored in `/data/tiles/`. To make sure that this data survives container restarts, you should create another volume for it:

```
docker volume create osm-tiles
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    -v osm-tiles:/data/tiles/ \
    -d overv/openstreetmap-tile-server \
    run
```

**If you do this, then make sure to also run the import with the `osm-tiles` volume to make sure that caching works properly across updates!**

### Enabling automatic updating (optional)

Given that you've set up your import as described in the *Automatic updates* section during server setup, you can enable the updating process by setting the `UPDATES` variable while running your server as well:

```
docker run \
    -p 8080:80 \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/minute/ \
    -e MAX_INTERVAL_SECONDS=60 \
    -e UPDATES=enabled \
    -v osm-data:/data/database/ \
    -v osm-tiles:/data/tiles/ \
    -d overv/openstreetmap-tile-server \
    run
```

This will enable a background process that automatically downloads changes from the OpenStreetMap server, filters them for the relevant region polygon you specified, updates the database and finally marks the affected tiles for rerendering.

### Tile expiration (optional)

Specify custom tile expiration settings to control which zoom level tiles are marked as expired when an update is performed. Tiles can be marked as expired in the cache (TOUCHFROM), but will still be served
until a new tile has been rendered, or deleted from the cache (DELETEFROM), so nothing will be served until a new tile has been rendered.

The example tile expiration values below are the default values.

```
docker run \
    -p 8080:80 \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/minute/ \
    -e MAX_INTERVAL_SECONDS=60 \
    -e UPDATES=enabled \
    -e EXPIRY_MINZOOM=13 \
    -e EXPIRY_TOUCHFROM=13 \
    -e EXPIRY_DELETEFROM=19 \
    -e EXPIRY_MAXZOOM=20 \
    -v osm-data:/data/database/ \
    -v osm-tiles:/data/tiles/ \
    -d overv/openstreetmap-tile-server \
    run
```

### Cross-origin resource sharing

To enable the `Access-Control-Allow-Origin` header to be able to retrieve tiles from other domains, simply set the `ALLOW_CORS` variable to `enabled`:

```
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    -e ALLOW_CORS=enabled \
    -d overv/openstreetmap-tile-server \
    run
```

### Connecting to Postgres

To connect to the PostgreSQL database inside the container, make sure to expose port 5432:

```
docker run \
    -p 8080:80 \
    -p 5432:5432 \
    -v osm-data:/data/database/ \
    -d overv/openstreetmap-tile-server \
    run
```

Use the user `renderer` and the database `gis` to connect.

```
psql -h localhost -U renderer gis
```

The default password is `renderer`, but it can be changed using the `PGPASSWORD` environment variable:

```
docker run \
    -p 8080:80 \
    -p 5432:5432 \
    -e PGPASSWORD=secret \
    -v osm-data:/data/database/ \
    -d overv/openstreetmap-tile-server \
    run
```

## Performance tuning and tweaking

Details for update procedure and invoked scripts can be found here [link](https://ircama.github.io/osm-carto-tutorials/updating-data/).

### THREADS

The import and tile serving processes use 4 threads by default, but this number can be changed by setting the `THREADS` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e THREADS=24 \
    -v osm-data:/data/database/ \
    -d overv/openstreetmap-tile-server \
    run
```

### CACHE

The import and tile serving processes use 800 MB RAM cache by default, but this number can be changed by option -C. For example:
```
docker run \
    -p 8080:80 \
    -e "OSM2PGSQL_EXTRA_ARGS=-C 4096" \
    -v osm-data:/data/database/ \
    -d overv/openstreetmap-tile-server \
    run
```

### AUTOVACUUM

The database use the autovacuum feature by default. This behavior can be changed with `AUTOVACUUM` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e AUTOVACUUM=off \
    -v osm-data:/data/database/ \
    -d overv/openstreetmap-tile-server \
    run
```

### FLAT_NODES

If you are planning to import the entire planet or you are running into memory errors then you may want to enable the `--flat-nodes` option for osm2pgsql. You can then use it during the import process as follows:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v osm-data:/data/database/ \
    -e "FLAT_NODES=enabled" \
    overv/openstreetmap-tile-server \
    import
```

Warning: enabling `FLAT_NOTES` together with `UPDATES` only works for entire planet imports (without a `.poly` file).  Otherwise this will break the automatic update script. This is because trimming the differential updates to the specific regions currently isn't supported when using flat nodes.

### Benchmarks

You can find an example of the import performance to expect with this image on the [OpenStreetMap wiki](https://wiki.openstreetmap.org/wiki/Osm2pgsql/benchmarks#debian_9_.2F_openstreetmap-tile-server).

## Troubleshooting

### ERROR: could not resize shared memory segment / No space left on device

If you encounter such entries in the log, it will mean that the default shared memory limit (64 MB) is too low for the container and it should be raised:
```
renderd[121]: ERROR: failed to render TILE default 2 0-3 0-3
renderd[121]: reason: Postgis Plugin: ERROR: could not resize shared memory segment "/PostgreSQL.790133961" to 12615680 bytes: ### No space left on device
```
To raise it use `--shm-size` parameter. For example:
```
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    --shm-size="192m" \
    -d overv/openstreetmap-tile-server \
    run
```
For too high values you may notice excessive CPU load and memory usage. It might be that you will have to experimentally find the best values for yourself.

### The import process unexpectedly exits

You may be running into problems with memory usage during the import. Have a look at the "Flat nodes" section in this README.

## License

```
Copyright 2019 Alexander Overvoorde

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
