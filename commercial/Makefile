CLIENT_TOOLS_IMAGE := artifactory.delivery.puppetlabs.net/platform-services-297419/pe-and-platform/pe-client-tools:latest
NAMESPACE ?= INVALID_NS
MAKE_TARGETS ?= lint build test publish
CREATE_REPO_IN_ARTIFACTORY ?= true
export PRELOAD_CERTS ?= 1

build_release: export NAMESPACE := $(NAMESPACE)
build_release: export LATEST_VERSION := pe-$(PE_RELEASE)
build_release: export PE_BRANCH := $(PE_RELEASE)
build_release: export REPO_NAME := debian_pupperware__local
build_release: export IS_LATEST := true
build_release:
	$(if $(PE_RELEASE),,$(error $$PE_RELEASE must be set))
	rm -rf tmp
	mkdir tmp
ifeq ($(CREATE_REPO_IN_ARTIFACTORY),true)
	wget -O tmp/pe.tar.gz https://artifactory.delivery.puppetlabs.net/artifactory/generic_enterprise__local/archives/releases/$(PE_RELEASE)/puppet-enterprise-$(PE_RELEASE)-ubuntu-18.04-amd64.tar.gz
	tar xf tmp/pe.tar.gz --directory tmp --strip-components=1
	cd tmp/packages/ubuntu-18.04-amd64 && for i in `ls`; do \
		curl -X PUT "https://artifactory.delivery.puppetlabs.net/artifactory/debian_pupperware__local/$(PE_RELEASE)/ubuntu-18.04-amd64/$$i;deb.component=$${PE_RELEASE//\./_};deb.architecture=amd64;deb.distribution=bionic" -T $$i; done
endif
	git clone git@github.com:puppetlabs/pe-puppetserver tmp/pe-puppetserver
	cd tmp/pe-puppetserver/docker && PE_DEB_COMPONENT=$${PE_RELEASE//\./_} $(MAKE) $(MAKE_TARGETS)
	git clone git@github.com:puppetlabs/pe-puppetdb-extensions tmp/pe-puppetdb-extensions
	cd tmp/pe-puppetdb-extensions/docker && PE_DEB_COMPONENT=$${PE_RELEASE//\./_} $(MAKE) $(MAKE_TARGETS)
	git clone git@github.com:puppetlabs/pe-console-services tmp/pe-console-services
	cd tmp/pe-console-services/docker && PE_DEB_COMPONENT=$${PE_RELEASE//\./_} $(MAKE) $(MAKE_TARGETS)
	git clone git@github.com:puppetlabs/pe-orchestration-services tmp/pe-orchestration-services
	cd tmp/pe-orchestration-services/docker && PE_DEB_COMPONENT=$${PE_RELEASE//\./_} $(MAKE) $(MAKE_TARGETS)
	git clone git@github.com:puppetlabs/pe-bolt-vanagon tmp/pe-bolt-vanagon
	cd tmp/pe-bolt-vanagon/docker && PE_DEB_COMPONENT=$${PE_RELEASE//\./_} $(MAKE) $(MAKE_TARGETS)
	git clone git@github.com:puppetlabs/pe-client-tools-vanagon tmp/pe-client-tools-vanagon
	cd tmp/pe-client-tools-vanagon/docker && PE_DEB_COMPONENT=$${PE_RELEASE//\./_} $(MAKE) $(MAKE_TARGETS)

pull:
	docker-compose pull --ignore-pull-failures
	docker pull $(CLIENT_TOOLS_IMAGE)

test:
	bundle install --path .bundle/gems --with test
	bundle update
	bundle exec rspec spec/

up:
	docker-compose up

down:
	docker-compose down --volumes --remove-orphans

start:
	docker-compose start

stop:
	docker-compose stop

logs:
	docker-compose logs --follow

console:
	open https://localhost

client:
	@docker run -ti --rm \
		--network pupperware-commercial \
		--env RBAC_USERNAME=admin \
		--env RBAC_PASSWORD=pupperware \
		--env PUPPETSERVER_HOSTNAME=puppet \
		--env PUPPETDB_HOSTNAME=puppetdb \
		--env PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services \
		--env PE_ORCHESTRATION_SERVICES_HOSTNAME=pe-orchestration-services \
		$(CLIENT_TOOLS_IMAGE)

.PHONY: pull test up down start stop logs console client
