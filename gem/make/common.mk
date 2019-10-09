VERSION ?= $(shell git describe | sed 's/-.*//')
vcs_ref := $(shell git rev-parse HEAD)
build_date := $(shell date -u +%FT%T)
hadolint_available := $(shell hadolint --help > /dev/null 2>&1; echo $$?)

.PHONY: network-access prep cleanup lint build test publish push-image push-readme pull up down start stop

network-access:
ifneq ($(TRAVIS),true)
	@curl https://artifactory.delivery.puppetlabs.net/artifactory/api/system/ping \
		--connect-timeout 1 --silent --output /dev/null \
	|| (echo 'ERROR: Artifactory cannot be reached or unhealthy. Are you on the VPN?' >&2; exit 1)
endif
