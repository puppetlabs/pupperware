NAMESPACE ?= puppet
vcs_ref := $(shell git rev-parse HEAD)
build_date := $(shell date -u +%FT%T)
version := latest
dockerfile := Dockerfile
hadolint_available := $(shell hadolint --help > /dev/null 2>&1; echo $$?)
hadolint_command := hadolint --ignore DL3008 --ignore DL3018 --ignore DL4000 --ignore DL4001
hadolint_container := hadolint/hadolint:latest

lint:
ifeq ($(hadolint_available),0)
	@$(hadolint_command) $(dockerfile)
else
	@docker pull $(hadolint_container)
	@docker run --rm -v $(PWD)/$(dockerfile):/Dockerfile \
		-i $(hadolint_container) $(hadolint_command) Dockerfile
endif

build:
	@docker build \
		--pull \
		--build-arg vcs_ref=$(vcs_ref) \
		--build-arg build_date=$(build_date) \
		--build-arg version=$(version) \
		--file $(dockerfile) \
	  --tag $(NAMESPACE)/ssl-sidecar:$(version) \
		..

test:
	@echo "TODO: spec tests"

push-image:
	@docker push $(NAMESPACE)/ssl-sidecar:$(version)

publish: push-image

.PHONY: lint build test publish push-image
