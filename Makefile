SHELL=/bin/bash
ELASTIC_VERSION := $(shell ./bin/elastic-version)

TEDI_DEBUG ?= false
TEDI_VERSION ?= 0.7
TEDI ?= docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(PWD):/mnt \
  -v $(PWD)/../..:/release-manager \
  -e TEDI_DEBUG=$(TEDI_DEBUG) \
  docker.elastic.co/tedi/tedi:$(TEDI_VERSION)

export PATH := ./bin:./venv/bin:$(PATH)

PYTHON ?= $(shell command -v python3.5 || command -v python3.6)
FIGLET := pyfiglet -w 160 -f puffy

# Build different images for OSS-only and full versions.
IMAGE_FLAVORS ?= oss full

default: from-release

test: lint
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  $(FIGLET) "test: $(FLAVOR)"; \
	  ./bin/pytest tests --image-flavor=$(FLAVOR); \
	)

# Test a snapshot image, which requires modifying the ELASTIC_VERSION to find the right images.
test-snapshot:
	ELASTIC_VERSION=$(ELASTIC_VERSION)-SNAPSHOT make test

lint: venv
	  flake8 tests

clean:
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  COMPOSE_FILE=".tedi/build/elasticsearch-$(FLAVOR)/docker-compose.yml"; \
	  if [[ -f $$COMPOSE_FILE ]]; then \
	    docker-compose -f $$COMPOSE_FILE down && docker-compose -f $$COMPOSE_FILE rm -f -v; \
	  fi; \
	)
	$(TEDI) clean --clean-assets

# Build images from releases on www.elastic.co
# The ELASTIC_VERSION specified in this file might not have been released yet,
# so you may need to override it.
from-release:
	$(TEDI) build --fact=elastic_version:$(ELASTIC_VERSION) \
	              --fact=image_tag:$(ELASTIC_VERSION)

# Build images from snapshots on snapshots.elastic.co
from-snapshot:
	$(TEDI) build --asset-set=remote_snapshot \
                      --fact=elastic_version:$(ELASTIC_VERSION) \
	              --fact=image_tag:$(ELASTIC_VERSION)-SNAPSHOT

# Build release images from within the Release Manager.
release-manager-release: clean
	$(TEDI) build --asset-set=local_release \
	              --fact=elastic_version:$(ELASTIC_VERSION) \
	              --fact=image_tag:$(ELASTIC_VERSION)

# Build snapshot images from within the Release Manager.
release-manager-snapshot: clean
	$(TEDI) build --asset-set=local_snapshot \
	              --fact=elastic_version:$(ELASTIC_VERSION) \
	              --fact=image_tag:$(ELASTIC_VERSION)-SNAPSHOT

venv: requirements.txt
	test -d venv || virtualenv --python=$(PYTHON) venv
	pip install -r requirements.txt
	touch venv
