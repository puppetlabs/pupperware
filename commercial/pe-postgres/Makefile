NAMESPACE ?= artifactory.delivery.puppetlabs.net/pe-and-platform
VERSION ?= latest
vcs_ref := $(shell git rev-parse HEAD)
build_date := $(shell date -u +%FT%T)
hadolint_available := $(shell hadolint --help > /dev/null 2>&1; echo $$?)
hadolint_command := hadolint --ignore DL3008
#--ignore DL3018 --ignore DL4000 --ignore DL4001

lint:
ifeq ($(hadolint_available),0)
	@$(hadolint_command) Dockerfile
else
	@docker pull hadolint/hadolint:latest
	@docker run --rm -v $(PWD)/Dockerfile:/Dockerfile \
		-i hadolint/hadolint:latest $(hadolint_command) Dockerfile
endif

build:
	@docker build \
		--pull \
		--build-arg version=$(VERSION) \
		--build-arg vcs_ref=$(vcs_ref) \
		--build-arg build_date=$(build_date) \
		--file Dockerfile \
		--tag $(NAMESPACE)/pe-postgres:$(VERSION) \
		.

test:
	@echo "No tests"

push-image:
	@docker push $(NAMESPACE)/pe-postgres:$(VERSION)

publish: push-image

pull:
	@docker pull $(NAMESPACE)/pe-postgres:$(VERSION)

.PHONY: lint build test publish push-image pull
