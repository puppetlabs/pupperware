pull:
	docker-compose pull

test: pull
	bundle install --path .bundle/gems
	bundle update
	bundle exec rspec spec/

up: pull
	docker-compose up

down:
	docker-compose down --volumes

start:
	docker-compose start

stop:
	docker-compose stop

.PHONY: pull test up down start stop
