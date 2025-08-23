# Docker OpenStreetMap Tile Server

Docker-based OpenStreetMap PNG tile server that serves map tiles from OSM data using PostgreSQL, PostGIS, Apache, and renderd. Based on Ubuntu 22.04 and uses the openstreetmap-carto style by default.

**ALWAYS reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Working Effectively

### Quick Start - Using Pre-built Image (RECOMMENDED)
**CRITICAL**: Building from source often fails due to network restrictions. Always use the pre-built image first:

- Pull the official image: `docker pull overv/openstreetmap-tile-server:latest`
- Create database volume: `docker volume create osm-data`
- For testing: Use Luxembourg data (small, ~3MB download when network available)
- **NEVER CANCEL**: Import takes 5-15 minutes for Luxembourg, 45+ minutes for larger regions. ALWAYS set timeout to 60+ minutes minimum.

### Build from Source (OFTEN FAILS)
**WARNING**: Building from source frequently fails due to network restrictions:

- `make build` -- **OFTEN FAILS**: Network issues prevent PostgreSQL GPG key download and other dependencies
- **Fails after ~19 seconds** with error: "gpg: no valid OpenPGP data found"
- **Expected Error Message**: "failed to solve: process ... did not complete successfully: exit code: 2"
- **Root Cause**: Cannot resolve www.postgresql.org or download GPG keys
- **Workaround**: Use pre-built image `docker pull overv/openstreetmap-tile-server:latest`
- If build succeeds: takes 15-25 minutes. NEVER CANCEL. Set timeout to 45+ minutes.

### Import OSM Data
**CRITICAL TIMING**: Import is the most time-consuming operation.

**For Luxembourg (test/development):**
```bash
docker run --rm --shm-size=128M \
  -v osm-data:/data/database/ \
  -e UPDATES=enabled \
  overv/openstreetmap-tile-server:latest \
  import
```
- **Duration**: 5-15 minutes for Luxembourg (when network available)
- **Network Dependency**: **OFTEN FAILS** - Cannot resolve download.geofabrik.de
- **Fails after ~10 seconds** with: "wget: unable to resolve host address 'download.geofabrik.de'"
- **Database Setup**: Works correctly (PostgreSQL, PostGIS setup succeeds)
- **Workaround**: Pre-download .osm.pbf files and mount them
- **NEVER CANCEL**: Always set timeout to 30+ minutes when network available

**For larger regions:**
```bash
docker run --rm --shm-size=128M \
  -v /absolute/path/to/region.osm.pbf:/data/region.osm.pbf \
  -v osm-data:/data/database/ \
  overv/openstreetmap-tile-server:latest \
  import
```
- **Duration**: 45+ minutes for country-sized regions, 8+ hours for planet
- **NEVER CANCEL**: Set timeout to 120+ minutes minimum
- **Memory**: Use `--shm-size=128M` (minimum) or higher for larger imports

### Run Tile Server
```bash
docker run --shm-size=128M \
  -v osm-data:/data/database/ \
  -p 8080:80 \
  -d \
  overv/openstreetmap-tile-server:latest \
  run
```
- **Startup Time**: 30-60 seconds
- **Tile Generation**: First-time tile rendering takes 2-10 seconds per tile
- **Access**: `http://localhost:8080/tile/{z}/{x}/{y}.png`
- **Demo**: `http://localhost:8080` (leaflet-demo.html)

### Performance Tuning
**Threads**: Default 4, adjust with `-e THREADS=8`
**Cache**: Default 800MB, adjust with `-e "OSM2PGSQL_EXTRA_ARGS=-C 4096"`
**Shared Memory**: Use `--shm-size=192m` for better performance

## Validation Scenarios

### ALWAYS Test After Changes
**Complete End-to-End Validation:**
1. Import test data: `make test` (uses Luxembourg)
2. Verify container starts without errors: `docker logs <container>`
3. Test tile endpoints:
   ```bash
   curl http://localhost:8080/tile/0/0/0.png --fail -o test.png
   curl http://localhost:8080/tile/1/0/0.png --fail -o test2.png
   ```
4. Verify PNG format: `file test.png` should show "PNG image data"
5. Verify demo page loads: `curl http://localhost:8080` should return HTML

**Manual Validation Requirement:**
- **ALWAYS** test actual functionality after making changes
- **NEVER** assume the application works just because the container starts
- **Container Help Test**: `docker run --rm overv/openstreetmap-tile-server:latest` should show usage message
- **Database Setup Test**: Import process should successfully create PostgreSQL database and extensions
- **Expected Import Progression**: 1) Style setup (carto warnings OK), 2) DB init, 3) Download/import, 4) Index creation

**Network-Aware Validation:**
- **Pre-built Image Test**: `docker pull overv/openstreetmap-tile-server:latest` (should succeed)
- **Build Test**: `make build` (likely fails after ~19s with GPG error)
- **Import Test**: Import attempt (likely fails after ~10s with DNS error)
- **Document All Failures**: Always note exact error messages and timing for network issues

## Common Tasks

### Testing and Development
- `make build` -- Build image (15-25 min, often fails due to network)
- `make test` -- **OFTEN FAILS** at build stage due to network restrictions
- `make stop` -- Clean up test containers and volumes
- Check logs: `docker logs <container_name>`
- **Alternative Testing**: Use pre-built image with manual validation steps

### Network Limitations (CRITICAL)
**CRITICAL**: Many environments have network restrictions that prevent normal operation:

- **Building fails**: Cannot download PostgreSQL GPG keys (~19 seconds, exit code 2)
- **Import fails**: Cannot download OSM data files (~10 seconds, exit code 4)  
- **DNS Resolution**: Cannot resolve external hostnames (www.postgresql.org, download.geofabrik.de)
- **Workarounds Required**: 
  - Use pre-built images: `docker pull overv/openstreetmap-tile-server:latest`
  - Pre-download data files and mount them locally
  - Document network failures as expected behavior in restricted environments
- **Always document**: When commands fail due to network issues

### Environment Variables Reference
- `THREADS=4`: Number of processing threads (import/rendering)
- `UPDATES=enabled`: Enable automatic updates
- `PGPASSWORD=renderer`: Database password (default: renderer)
- `ALLOW_CORS=enabled`: Enable cross-origin requests
- `AUTOVACUUM=on`: Database auto-vacuum (default: on)
- `FLAT_NODES=enabled`: Use flat nodes for planet imports

### Common Troubleshooting
- **"No space left on device"**: Increase `--shm-size` parameter
- **Import exits unexpectedly**: Memory issues, try FLAT_NODES=enabled
- **Build fails with GPG errors**: Network restrictions, use pre-built image
- **Empty/identical tiles**: Check PostgreSQL logs, verify data import completed

## Repository Structure

```
docker-openstreetmap-tile-server/
├── Dockerfile              # Multi-stage Docker build
├── run.sh                   # Main entrypoint script (import|run)
├── Makefile                 # Build and test commands
├── docker-compose.yml       # Docker Compose configuration
├── README.md                # Comprehensive usage documentation
├── leaflet-demo.html        # Demo web interface
├── .github/workflows/       # CI/CD pipeline
│   └── build-and-test.yaml  # Builds both amd64/arm64, tests Luxembourg
├── apache.conf              # Apache configuration
├── postgresql.custom.conf.tmpl # PostgreSQL tuning
└── openstreetmap-tiles-update-expire.sh # Update script
```

### Key Processes
1. **Multi-stage build**: Downloads openstreetmap-carto style, regional scripts
2. **Import**: Sets up PostgreSQL, downloads/imports OSM data, creates indexes
3. **Run**: Starts PostgreSQL, Apache, renderd daemon for tile serving
4. **Rendering**: On-demand PNG tile generation at zoom levels 0-20

### GitHub Workflow Validation
The CI pipeline provides the definitive validation pattern:
1. Build image for amd64/arm64
2. Import Luxembourg test data (~5 min)
3. Start server (30 sec)
4. Download specific test tiles
5. Verify PNG format and uniqueness
6. Expected SHA: `c226ca747874fb1307eef853feaf9d8db28cef2b` for empty.png

**Always follow this validation pattern when testing changes.**

## Time Expectations Summary

| Operation | Network Available | Network Restricted | Notes |
|-----------|------------------|-------------------|-------|
| Build | 15-25 min | **FAILS ~19s** | GPG key download fails |
| Import (Luxembourg) | 5-15 min | **FAILS ~10s** | Data download fails |
| Import (Large Region) | 45-90 min | **FAILS ~10s** | Data download fails |
| Container Start | 30-60 sec | 30-60 sec | No network needed |
| First Tile Render | 2-10 sec | 2-10 sec | No network needed |
| Pre-built Pull | 1-10 sec | 1-10 sec | Docker Hub accessible |

**NEVER CANCEL any operation before these minimum times. Always add 50% buffer to timeouts.**

**Network Restriction Indicators:**
- Build fails: "gpg: no valid OpenPGP data found" after ~19 seconds
- Import fails: "wget: unable to resolve host address" after ~10 seconds
- Both indicate DNS/firewall restrictions requiring pre-built images and local data