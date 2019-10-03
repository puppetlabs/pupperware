pull:
	docker-compose pull --ignore-pull-failures

test:
	bundle install --path .bundle/gems
	bundle update
	bundle exec rspec spec/

up: pull
	docker-compose up

down:
	docker-compose down --volumes --remove-orphans

start:
	docker-compose start

stop:
	docker-compose stop

.PHONY: pull test up down start stop
