.PHONY: build push test osm-bright-build test-prerender-europe

DOCKER_IMAGE=overv/openstreetmap-tile-server
BIQAPS_IMAGE=biqaps/openstreetmap:3.0

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

test-prerender-europe: osm-bright-build
	docker volume create osm-data-europe
	docker run --rm --shm-size=192m -v osm-data-europe:/data/database/ \
		-e STYLE_TYPE=osm-bright \
		-e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
		${BIQAPS_IMAGE} import
	docker run --rm --shm-size=192m -v osm-data-europe:/data/database/ \
		-e STYLE_TYPE=osm-bright \
		-e PRERENDER_REGION=luxembourg \
		-e PRERENDER_MIN_ZOOM=0 \
		-e PRERENDER_MAX_ZOOM=8 \
		-e PRERENDER_THREADS=4 \
		${BIQAPS_IMAGE} prerender

stop:
	docker rm -f `docker ps | grep '${DOCKER_IMAGE}' | awk '{ print $$1 }'` || true
	docker rm -f `docker ps | grep '${BIQAPS_IMAGE}' | awk '{ print $$1 }'` || true
	docker volume rm -f osm-data
	docker volume rm -f osm-data-bright
	docker volume rm -f osm-data-europe
