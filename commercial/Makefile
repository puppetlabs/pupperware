CLIENT_TOOLS_IMAGE := artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:latest

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
