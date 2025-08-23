# GitHub Copilot Instructions for OpenStreetMap Tile Server

## Project Overview

This repository contains a Docker-based OpenStreetMap tile server that allows users to easily set up a PNG tile server from OSM data files (`.osm.pbf`). The project is based on Ubuntu and supports multiple map styles including the default OpenStreetMap Carto style and OSM-Bright style, with special support for GeoDanmark integration.

## Architecture & Key Components

### Core Components
- **Dockerfile**: Multi-stage Docker build with specialized stages for external data, stylesheets, and helper scripts
- **run.sh**: Main entrypoint script that handles both import and run operations
- **Apache + mod_tile**: Web server configuration for serving tiles at `/tile/{z}/{x}/{y}.png`
- **PostgreSQL + PostGIS**: Database for storing OSM data with spatial extensions
- **Mapnik**: Rendering engine for generating map tiles
- **osm2pgsql**: Tool for importing OSM data into PostgreSQL

### Map Styles
1. **openstreetmap-carto**: Default style (gravitystorm/openstreetmap-carto v5.4.0)
2. **osm-bright**: Minimalist style from Mapbox with GeoDanmark support

### Key Files
- `Dockerfile`: Multi-stage container build configuration
- `run.sh`: Main script with import/run commands and style management
- `apache.conf`: Apache configuration for tile serving
- `postgresql.custom.conf.tmpl`: PostgreSQL configuration template
- `openstreetmap-tiles-update-expire.sh`: Script for automatic tile updates
- `leaflet-demo.html`: Demo web interface for viewing tiles
- `docker-compose.yml`: Simplified deployment configuration
- `Makefile`: Local development and testing commands

## Development Workflow

### Building the Image
```bash
# Standard build
make build

# OSM-Bright style build
make osm-bright-build

# Direct Docker build
docker build -t overv/openstreetmap-tile-server .
```

### Testing
```bash
# Test standard style
make test

# Test OSM-Bright style
make test-osm-bright

# Manual testing
docker volume create osm-data
docker run --rm -v osm-data:/data/database/ overv/openstreetmap-tile-server import
docker run --rm -v osm-data:/data/database/ -p 8080:80 -d overv/openstreetmap-tile-server run
```

### CI/CD
- GitHub Actions workflow at `.github/workflows/build-and-test.yaml`
- Automated testing with Luxembourg data import and tile generation
- Multi-platform builds (amd64)
- Automated publishing to Docker Hub and GitHub Container Registry

## Environment Variables

### Import/Run Behavior
- `DOWNLOAD_PBF`: URL to download OSM PBF data file
- `DOWNLOAD_POLY`: URL to download polygon boundary file for updates
- `UPDATES`: Enable automatic updates (`enabled`/`disabled`)
- `THREADS`: Number of threads for importing and rendering (default: 4)

### Style Configuration
- `STYLE_TYPE`: Map style (`openstreetmap-carto` or `osm-bright`)
- `NAME_LUA`: Custom Lua script name (default: `openstreetmap-carto.lua`)
- `NAME_STYLE`: Custom style file name (default: `openstreetmap-carto.style`)
- `NAME_MML`: Custom MML file name (default: `project.mml`)
- `NAME_SQL`: Custom SQL file name (default: `openstreetmap-carto.sql`)

### Database Configuration
- `AUTOVACUUM`: PostgreSQL autovacuum setting (`on`/`off`)
- `PGPASSWORD`: PostgreSQL password (default: `renderer`)
- `FLAT_NODES`: Use flat nodes for memory efficiency
- `CACHE`: osm2pgsql cache size

### Special Features
- `DOWNLOAD_GEODANMARK`: Enable GeoDanmark shapefile download (`enabled`)
- `REPLICATION_URL`: OSM replication server URL
- `MAX_INTERVAL_SECONDS`: Maximum update interval (default: 3600)

## File Structure & Conventions

### Container Paths
- `/data/database/`: PostgreSQL data directory (mounted volume)
- `/data/style/`: Map style files directory
- `/data/external-data/`: External data files (land polygons, etc.)
- `/var/cache/renderd/tiles/`: Tile cache directory
- `/home/renderer/src/`: Source code and styles

### Volume Mounts
- Primary data volume: `osm-data:/data/database/`
- Style volume (optional): `<local-style-path>:/data/style/`

## Coding Conventions

### Shell Scripts
- Use `set -euo pipefail` for error handling
- Function names in camelCase (e.g., `createPostgresConfig`)
- Environment variable checks with `${VAR:-default}` syntax
- Proper quoting of variables to prevent word splitting

### Docker Best Practices
- Multi-stage builds to minimize final image size
- Non-interactive package installation (`DEBIAN_FRONTEND=noninteractive`)
- Proper layer caching optimization
- Security considerations (non-root user where possible)

### Configuration Files
- Template files use `.tmpl` extension
- Configuration generated at runtime in `/etc/` directories
- Proper file permissions and ownership

## Common Development Tasks

### Adding New Map Style Support
1. Create new stage in Dockerfile for style compilation
2. Add style detection logic in `run.sh`
3. Update environment variable documentation
4. Add test case in Makefile and GitHub Actions

### Modifying Database Configuration
1. Update `postgresql.custom.conf.tmpl`
2. Modify `createPostgresConfig()` function in `run.sh`
3. Test with various data sizes and update scenarios

### Adding New Environment Variables
1. Document in `run.sh` help text
2. Add to README.md environment variables section
3. Update GitHub Actions workflow if needed for testing

## Performance Considerations

### Memory Usage
- PostgreSQL shared_buffers configuration
- osm2pgsql cache settings
- Flat nodes option for large imports

### Storage
- PostgreSQL autovacuum settings
- Tile cache management
- Data volume optimization

### Rendering
- Thread count optimization
- Mapnik rendering settings
- Apache mod_tile configuration

## Security Notes

- PostgreSQL runs with restricted access
- Apache serves only tile endpoints
- No direct database access from web interface
- Proper file permissions in container

## Dependencies & Versions

### Major Components
- Ubuntu 22.04 LTS base image
- PostgreSQL 15 with PostGIS 3
- Python 3 with mapnik bindings
- Node.js with carto 1.2.0
- Apache 2 with mod_tile

### External Data Sources
- OSM data from Geofabrik
- Land polygons from OpenStreetMap
- GeoDanmark from kortforsyningen.dk

## Troubleshooting Common Issues

### Memory Issues
- Check shared memory settings (`--shm-size=128M`)
- Verify available disk space
- Consider flat nodes for large imports

### Import Failures
- Verify PBF file integrity
- Check PostgreSQL configuration
- Monitor disk space during import

### Rendering Issues
- Verify style files are properly mounted
- Check mapnik.xml generation
- Validate font availability

## Testing Guidelines

### Unit Testing
- Test import with small datasets (Luxembourg)
- Verify tile generation at multiple zoom levels
- Check both styles work correctly

### Integration Testing
- Test with realistic data sizes
- Verify update functionality
- Check persistent volume behavior

### Performance Testing
- Benchmark import times
- Test concurrent tile requests
- Monitor memory usage patterns