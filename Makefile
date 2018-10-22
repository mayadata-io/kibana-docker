SHELL=/bin/bash
ELASTIC_REGISTRY ?= mayadataio

export PATH := ./bin:./venv/bin:$(PATH)

# Determine the version to build. Override by setting ELASTIC_VERSION env var.
ELASTIC_VERSION := 6.4.0

ifdef STAGING_BUILD_NUM
  VERSION_TAG=$(ELASTIC_VERSION)-${STAGING_BUILD_NUM}
else
  VERSION_TAG=$(ELASTIC_VERSION)
endif

PYTHON ?= $(shell command -v python3.5 || command -v python3.6)

# Build different images for OSS-only and full versions.
IMAGE_FLAVORS ?= oss full

# Which image will get the default, unqualified name?
DEFAULT_IMAGE_FLAVOR ?= full

IMAGE_TAG ?= $(ELASTIC_REGISTRY)/kibana/kibana
HTTPD ?= kibana-docker-artifact-server

FIGLET := pyfiglet -w 160 -f puffy

all: build test

test: lint docker-compose
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  $(FIGLET) "test: $(FLAVOR)"; \
	  ./bin/pytest tests --image-flavor=$(FLAVOR); \
	)

# Test a snapshot image, which requires modifying the ELASTIC_VERSION to find the right images.
test-snapshot:
	# We need 'oss' and 'full' versions of Elasticsearch, but there's no explicit '-full'
	# on the registry. Pull the unqualified name and tag it as '-full'.
	docker pull $(ELASTIC_REGISTRY)/elasticsearch/elasticsearch:$(ELASTIC_VERSION)-SNAPSHOT
	docker tag $(ELASTIC_REGISTRY)/elasticsearch/elasticsearch{,-full}:$(ELASTIC_VERSION)-SNAPSHOT
	ELASTIC_VERSION=$(ELASTIC_VERSION)-SNAPSHOT make test

lint: venv
	  flake8 tests

build: dockerfile
	docker pull centos:7
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  $(FIGLET) "build: $(FLAVOR)"; \
	  docker build -t $(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG) \
	    -f build/kibana/Dockerfile-$(FLAVOR) build/kibana; \
	  if [[ $(FLAVOR) == $(DEFAULT_IMAGE_FLAVOR) ]]; then \
	    docker tag $(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG) $(IMAGE_TAG):$(VERSION_TAG); \
	  fi; \
	)

release-manager-snapshot: clean
	ARTIFACTS_DIR=$(ARTIFACTS_DIR) ELASTIC_VERSION=$(ELASTIC_VERSION)-SNAPSHOT make build-from-local-artifacts

release-manager-release: clean
	ARTIFACTS_DIR=$(ARTIFACTS_DIR) ELASTIC_VERSION=$(ELASTIC_VERSION) make build-from-local-artifacts

# Build from artifacts on the local filesystem, using an http server (running
# in a container) to provide the artifacts to the Dockerfile.
build-from-local-artifacts: venv dockerfile docker-compose
	docker run --rm -d --name=$(HTTPD) \
	           --network=host -v $(ARTIFACTS_DIR):/mnt \
	           python:3 bash -c 'cd /mnt && python3 -m http.server'
	timeout 120 bash -c 'until curl -s localhost:8000 > /dev/null; do sleep 1; done'
	-$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  pyfiglet -f puffy -w 160 "Building: $(FLAVOR)"; \
	  docker build --network=host -t $(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG) -f build/kibana/Dockerfile-$(FLAVOR) build/kibana || \
	    (docker kill $(HTTPD); false); \
	  if [[ $(FLAVOR) == $(DEFAULT_IMAGE_FLAVOR) ]]; then \
	    docker tag $(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG) $(IMAGE_TAG):$(VERSION_TAG); \
	  fi; \
	)
	-docker kill $(HTTPD)

# Build images from the latest snapshots on snapshots.elastic.co
from-snapshot:
	rm -rf snapshots
	mkdir -p snapshots/kibana/target
	(cd snapshots/kibana/target && \
	  cp $$HOME/kibana-build/target/kibana-oss-6.4.0-SNAPSHOT-linux-x86_64.tar.gz .)
	ARTIFACTS_DIR=$$PWD/snapshots make release-manager-snapshot

# Push the image to the dedicated push endpoint at "push.docker.elastic.co"
push: test
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  docker tag $(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG) push.$(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG); \
	  docker push push.$(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG); \
	  docker rmi push.$(IMAGE_TAG)-$(FLAVOR):$(VERSION_TAG); \
	)
	# Also push the default version, with no suffix like '-oss' or '-full'
	docker tag $(IMAGE_TAG):$(VERSION_TAG) push.$(IMAGE_TAG):$(VERSION_TAG);
	docker push push.$(IMAGE_TAG):$(VERSION_TAG);
	docker rmi push.$(IMAGE_TAG):$(VERSION_TAG);

clean-test:
	$(TEST_COMPOSE) down
	$(TEST_COMPOSE) rm --force

venv: requirements.txt
	test -d venv || virtualenv --python=$(PYTHON) venv
	pip install -r requirements.txt
	touch venv

# Generate the Dockerfiles from Jinja2 templates.
dockerfile: venv templates/Dockerfile.j2
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  jinja2 \
	    -D image_flavor='$(FLAVOR)' \
	    -D elastic_version='$(ELASTIC_VERSION)' \
	    -D staging_build_num='$(STAGING_BUILD_NUM)' \
	    -D artifacts_dir='$(ARTIFACTS_DIR)' \
	    templates/Dockerfile.j2 > build/kibana/Dockerfile-$(FLAVOR); \
	)

# Generate docker-compose files from Jinja2 templates.
docker-compose: venv
	$(foreach FLAVOR, $(IMAGE_FLAVORS), \
	  jinja2 \
	    -D version_tag='$(VERSION_TAG)' \
	    -D image_flavor='$(FLAVOR)' \
	   templates/docker-compose.yml.j2 > docker-compose-$(FLAVOR).yml; \
	)
	ln -sf docker-compose-$(DEFAULT_IMAGE_FLAVOR).yml docker-compose.yml

.PHONY: build clean flake8 push pytest test dockerfile docker-compose
