# Build the RouterOS CHR image for containerlab's `mikrotik_ros` kind.
# Produces docker image: vrnetlab/mikrotik_routeros:$(VERSION)
#
# Override the version on the command line:  make build VERSION=7.22

VERSION ?= 7.23.1
IMAGE   := vrnetlab/mikrotik_routeros:$(VERSION)
PY      := python3

.DEFAULT_GOAL := build

.PHONY: build download extract image check clean distclean help

build: ## Full flow: download CHR, convert, build the vrnetlab image
	$(PY) build.py all --version $(VERSION)

download: ## Download the CHR VMDK image only
	$(PY) build.py download --version $(VERSION)

extract: ## Unzip the downloaded VMDK
	$(PY) build.py extract --version $(VERSION)

image: ## Build the vrnetlab docker image from the VMDK
	$(PY) build.py image --version $(VERSION)

check: ## Report whether the docker image exists
	@docker image inspect $(IMAGE) >/dev/null 2>&1 \
		&& echo "present: $(IMAGE)" \
		|| { echo "missing: $(IMAGE) — run 'make build'"; exit 1; }

clean: ## Remove downloaded/intermediate artifacts (keeps the vrnetlab clone)
	rm -f chr-*.zip chr-*.part chr-*.vmdk chr-*.img chr-*.qcow2

distclean: clean ## Also remove the vrnetlab clone
	rm -rf vrnetlab

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
