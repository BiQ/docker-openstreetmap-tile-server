.PHONY: build push test osm-bright-build

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

stop:
	docker rm -f `docker ps | grep '${DOCKER_IMAGE}' | awk '{ print $$1 }'` || true
	docker rm -f `docker ps | grep '${BIQAPS_IMAGE}' | awk '{ print $$1 }'` || true
	docker volume rm -f osm-data
	docker volume rm -f osm-data-bright
