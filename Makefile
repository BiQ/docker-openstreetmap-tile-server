.PHONY: build push test osm-bright-build prerender-denmark-osm-bright setup-denmark-osm-bright

DOCKER_IMAGE=overv/openstreetmap-tile-server
BIQAPS_IMAGE=biqaps/openstreetmap:3.1

# Denmark bounds (approximate)
DENMARK_MIN_LAT=54.4
DENMARK_MAX_LAT=57.8
DENMARK_MIN_LON=8.0
DENMARK_MAX_LON=15.2

# Prerendering configuration
MIN_ZOOM=0
MAX_ZOOM=15
RENDER_THREADS=4

build:
	docker build -t ${DOCKER_IMAGE} .

osm-bright-build:
	docker build -t ${BIQAPS_IMAGE} .

push: build
	docker push ${DOCKER_IMAGE}:latest

osm-bright-push: osm-bright-build
	docker push ${BIQAPS_IMAGE}

test: build
	docker volume create osm-data
	docker run --rm -v osm-data:/data/database/ ${DOCKER_IMAGE} import
	docker run --rm -v osm-data:/data/database/ -p 8080:80 -d ${DOCKER_IMAGE} run

test-osm-bright: osm-bright-build
	docker volume create osm-data-bright
	docker run --rm -v osm-data-bright:/data/database/ -e STYLE_TYPE=osm-bright ${BIQAPS_IMAGE} import
	docker run --rm -v osm-data-bright:/data/database/ -p 8081:80 -e STYLE_TYPE=osm-bright -d ${BIQAPS_IMAGE} run

stop:
	docker rm -f `docker ps | grep '${DOCKER_IMAGE}' | awk '{ print $$1 }'` || true
	docker rm -f `docker ps | grep '${BIQAPS_IMAGE}' | awk '{ print $$1 }'` || true
	docker volume rm -f osm-data
	docker volume rm -f osm-data-bright

setup-denmark-osm-bright: osm-bright-build
	@echo "Setting up Denmark OSM-Bright tile server..."
	docker volume create denmark-osm-data || true
	docker volume create denmark-style || true
	docker run --rm \
		-e STYLE_TYPE=osm-bright \
		-e DOWNLOAD_PBF=https://download.geofabrik.de/europe/denmark-latest.osm.pbf \
		-e DOWNLOAD_POLY=https://download.geofabrik.de/europe/denmark.poly \
		-e THREADS=${RENDER_THREADS} \
		-v denmark-osm-data:/data/database/ \
		-v denmark-style:/data/style/ \
		${BIQAPS_IMAGE} \
		import
	@echo "Denmark OSM data imported successfully!"

prerender-denmark-osm-bright: setup-denmark-osm-bright
	@echo "Starting prerendering of Denmark tiles (zoom ${MIN_ZOOM}-${MAX_ZOOM})..."
	@echo "This may take several hours depending on zoom levels and hardware."
	docker volume create denmark-tiles || true
	docker volume create denmark-style || true
	docker run --rm \
		-e STYLE_TYPE=osm-bright \
		-e THREADS=${RENDER_THREADS} \
		-v denmark-osm-data:/data/database/ \
		-v denmark-style:/data/style/ \
		-v denmark-tiles:/data/tiles/ \
		-v $(PWD)/scripts:/scripts \
		--entrypoint bash \
		${BIQAPS_IMAGE} \
		-c "/scripts/prerender-tiles.sh ${DENMARK_MIN_LAT} ${DENMARK_MIN_LON} ${DENMARK_MAX_LAT} ${DENMARK_MAX_LON} ${MIN_ZOOM} ${MAX_ZOOM}"
	@echo "Prerendering completed! Tiles are stored in denmark-tiles volume."

# Quick prerender for testing (zoom 0-6)
prerender-denmark-test:
	@echo "Starting test prerendering of Denmark tiles (zoom 0-6)..."
	$(MAKE) prerender-denmark-osm-bright MIN_ZOOM=0 MAX_ZOOM=6

# Full prerender for production (zoom 0-18)
prerender-denmark-full:
	@echo "Starting full prerendering of Denmark tiles (zoom 0-18)..."
	@echo "WARNING: This will generate millions of tiles and take many hours!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(MAKE) prerender-denmark-osm-bright MIN_ZOOM=0 MAX_ZOOM=18

run-denmark-osm-bright:
	@echo "Starting Denmark OSM-Bright tile server..."
	docker run --rm \
		-p 8080:80 \
		-e STYLE_TYPE=osm-bright \
		-v denmark-osm-data:/data/database/ \
		-v denmark-style:/data/style/ \
		-v denmark-tiles:/data/tiles/ \
		-d ${BIQAPS_IMAGE} \
		run
	@echo "Denmark tile server running at http://localhost:8080"

clean-denmark:
	@echo "Stopping and removing all containers using Denmark volumes..."
	@docker ps -a --filter volume=denmark-osm-data --filter volume=denmark-style --filter volume=denmark-tiles -q | xargs -r docker rm -f
	@echo "Removing Denmark volumes..."
	docker volume rm -f denmark-osm-data denmark-style denmark-tiles || true
